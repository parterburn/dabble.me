import PhotosUI
import SwiftUI

struct ComposeView: View {
    enum Mode {
        case new
        /// Only for entries with a `document` (see EntryDetail).
        case edit(EntryDetail)
    }

    let mode: Mode
    var onSaved: (EntryDetail) -> Void = { _ in }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editor: RichTextEditorModel
    @State private var date = Date()
    @State private var photoItems: [PhotosPickerItem] = []
    /// Prepared photos keyed by picker item, so re-selecting doesn't redo the work.
    @State private var prepared: [PhotosPickerItem: PreparedPhoto] = [:]
    /// Decoded once from each photo's small thumbnail, never from the full-size data.
    @State private var previews: [PhotosPickerItem: Image] = [:]
    @State private var isLoadingPhotos = false
    @State private var isSaving = false
    @State private var uploadedCount: Int?
    @State private var error: String?
    @State private var confirmingDiscard = false
    /// Moving the entry onto a day that has one: the server's words for it, while asking to merge.
    @State private var mergeQuestion: String?
    /// An unsaved draft from an earlier session was put back in the editor.
    @State private var restoredDraft: DraftStore.Draft?
    @State private var draftSave: Task<Void, Never>?
    @State private var isDiscarded = false
    /// The hashtag bar ("+" → Hashtags): AI suggestions first, then the most recently used tags.
    @State private var showsHashtagBar = false
    /// Prompt (Apple Intelligence, the sparkles): a row with one question about the draft. Closing
    /// and opening it again asks a new one.
    @State private var showsAskRow = false
    @State private var question: String?
    @State private var askedQuestions: [String] = []
    @State private var isAsking = false
    @State private var askError: String?
    /// The newest few entries (dated lines), as background for prompts; loaded with the first one.
    @State private var recentForPrompts: [String]?
    @State private var curatedPrompts: [String] = []
    /// The photo drawer (thumbnails, Add More, remove): closed unless opened from the photo stack,
    /// so the writing area keeps its room.
    @State private var showsPhotoDrawer = false
    @State private var recentTags: [String] = []
    /// Every hashtag the writer has used, to offer the ones the entry's words match.
    @State private var allTags: [String] = []
    @State private var suggestedTags: [String] = []
    @State private var isSuggestingTags = false
    @State private var suggestionError: String?
    @State private var pickingPhotos = false
    /// A free account tapped Photos: a note that they're part of PRO.
    @State private var explainingProPhotos = false
    @State private var takingPhoto = false
    /// Photos taken with the camera: they ride along in `photoItems` under made-up identifiers,
    /// which the photo picker doesn't know, so the picker works on `libraryItems` instead.
    @State private var cameraItems: [PhotosPickerItem] = []
    @State private var removesExistingPhoto = false
    @Environment(\.scenePhase) private var scenePhase
    private let draftKey: String
    /// Opened for a day of its own, which today's date doesn't then replace.
    private let startsOnDay: Bool
    private let originalBlocks: [DocumentBlock]

    /// `day`: a new entry for that day (Stats' grid), not today.
    init(mode: Mode, day: JournalDay? = nil, onSaved: @escaping (EntryDetail) -> Void = { _ in }) {
        self.mode = mode
        self.onSaved = onSaved
        startsOnDay = day != nil
        let entry: EntryDetail? = if case .edit(let entry) = mode { entry } else { nil }
        let original = entry?.document ?? []
        let key = DraftStore.key(forEntry: entry?.id)
        // Restore an unsaved draft, unless the entry has changed since (e.g. edited on the web).
        var draft = DraftStore.load(key)
        if let saved = draft, let entry,
           let updated = try? Date(entry.updatedAt, strategy: .iso8601), updated > saved.savedAt {
            draft = nil
            DraftStore.clear(key)
        }
        draftKey = key
        originalBlocks = original
        _restoredDraft = State(initialValue: draft)
        if let date = day ?? draft?.date.flatMap(JournalDay.init) ?? entry?.day { _date = State(initialValue: date.localDate) }
        _editor = State(initialValue: RichTextEditorModel(blocks: draft?.blocks ?? original))
    }

    private var isNew: Bool {
        if case .new = mode { true } else { false }
    }

    /// In the order the user picked them.
    private var photos: [PreparedPhoto] { photoItems.compactMap { prepared[$0] } }
    /// Editing: the day the entry is being moved to, when the date's been changed.
    private var movedTo: JournalDay? {
        guard case .edit(let entry) = mode else { return nil }
        let picked = JournalDay(localDate: date)
        return picked.iso == entry.date ? nil : picked
    }
    private var hasChanges: Bool { editor.isDirty || !photoItems.isEmpty || restoredDraft != nil || removesExistingPhoto || movedTo != nil }
    private var canSave: Bool {
        guard !isSaving, !isLoadingPhotos else { return false }
        return isNew ? (!editor.isEmpty || !photos.isEmpty)
            : (!editor.isEmpty && (editor.isDirty || restoredDraft != nil || !photos.isEmpty || removesExistingPhoto || movedTo != nil))
    }

    /// There are words to keep as a draft (a draft doesn't hold photos).
    private var canSaveDraft: Bool { !editor.isEmpty && (editor.isDirty || restoredDraft != nil) }

    /// Editing: the entry's photo (or collage) as it is now, unless removed. New photos join it in a collage.
    private var existingPhotoURL: URL? {
        guard case .edit(let entry) = mode, !removesExistingPhoto, !entry.imageProcessing else { return nil }
        return entry.summary.thumbnailURL(width: 168)
    }

    /// How many more photos fit (a collage holds `AppModel.maxPhotos`, counting the entry's own).
    private var photoLimit: Int { AppModel.maxPhotos - (existingPhotoURL == nil ? 0 : 1) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if restoredDraft != nil { draftBanner }
                if isSimplified { simplifiedBanner }
                Divider()
                RichTextEditor(model: editor,
                               leading: AnyView(model.me?.canAddPhotos == true ? AnyView(photosButton) : AnyView(proPhotosButton)),
                               trailing: AnyView(tagAndLinkButtons),
                               barKey: "\(attachedPhotoCount)|\(showsPhotoDrawer)|\(previews.count)|\(existingPhotoURL?.absoluteString ?? "")|\(showsHashtagBar)|\(showsAskRow)|\(canAsk)|\(editor.isEditingLink)",
                               row: openRow)
                    .overlay(alignment: .topLeading) {
                        if editor.isEmpty {
                            Text("How was your day?")
                                .font(Font(RichText.Style.journal.baseFont))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 16)
                                .padding(.leading, 17)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .overlay {
                if isSaving { savingOverlay }
            }
            .navigationTitle(isNew ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The date is the title, which leaves more room to write.
                ToolbarItem(placement: .principal) { dateTitle }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmingDiscard = true } else { discardDraft(); dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(hasChanges || isSaving)
            .confirmationDialog(isNew ? "Close this entry?" : "Close without saving your changes?",
                                isPresented: $confirmingDiscard, titleVisibility: .visible) {
                // A draft is kept on this device and comes back the next time this is opened.
                if canSaveDraft {
                    Button("Save Draft") {
                        draftSave?.cancel()
                        saveDraftNow()
                        dismiss()
                    }
                }
                Button("Discard", role: .destructive) {
                    discardDraft()
                    dismiss()
                }
                Button("Keep Writing", role: .cancel) {}
            } message: {
                if canSaveDraft {
                    Text(photoItems.isEmpty && !removesExistingPhoto
                        ? "A draft is kept on this device until you come back to it."
                        : "A draft keeps your words on this device until you come back to it, but not changes to photos.")
                }
            }
            // An alert, for its Cancel button (a confirmation dialog shows none here): Cancel puts
            // the date back to the entry's own day.
            .alert(mergeQuestion ?? "", isPresented: .present($mergeQuestion)) {
                Button("Merge", role: .destructive) { Task { await save(merging: true) } } // red: it can't be undone
                Button("Cancel", role: .cancel) {
                    if case .edit(let entry) = mode, let day = entry.day { date = day.localDate }
                }
            } message: {
                Text("Merging adds this entry to the end of that one, photo included. The two become one entry, which can't be undone.")
            }
            .alert("Couldn't save", isPresented: .present($error)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { image in Task { await addCameraPhoto(image) } }
                    .ignoresSafeArea()
            }
            .onChange(of: editor.isEditingLink) { _, editing in
                // One row at a time (the link row also opens by selecting a link).
                if editing { showsHashtagBar = false; showsAskRow = false; showsPhotoDrawer = false }
            }
            .photosPicker(isPresented: $pickingPhotos, selection: libraryItems, maxSelectionCount: photoLimit - cameraItems.count,
                          selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
            .alert("No hashtag suggestions", isPresented: .present($suggestionError)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(suggestionError ?? "")
            }
            .onChange(of: photoItems) { old, new in
                // Newly added photos go into the stack; the drawer closes to keep room for writing.
                if new.count > old.count { showsPhotoDrawer = false }
                Task { await preparePhotos() }
            }
            #if DEBUG
            .task { await attachDebugPhotos() }
            #endif
            .alert("Photos are a PRO feature", isPresented: $explainingProPhotos) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("With Dabble Me PRO you can add up to \(photoLimit) photos to an entry.")
            }
            .onChange(of: editor.revision) { scheduleDraftSave() }
            .onChange(of: date) { scheduleDraftSave() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { saveDraftNow() }
            }
            .onAppear {
                editor.allowsLinks = model.me?.mayAddLinks == true
                // Today's date in the journal's time zone, preferring the freshest source.
                if isNew, !startsOnDay, restoredDraft?.date == nil, let today = model.today?.day ?? model.me.flatMap({ JournalDay($0.today) }) {
                    date = today.localDate
                }
            }
            .task {
                // Give the sheet a moment to settle so the keyboard animates in with it.
                try? await Task.sleep(for: .milliseconds(350))
                editor.focus()
            }
        }
    }

    /// The entry's date, which can be changed: for a new entry, and to move one being edited to
    /// another day.
    private var dateTitle: some View {
        DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            .labelsHidden()
            .accessibilityLabel("Entry date")
    }

    /// The entry's photos: its current one (editing) and those being added.
    /// The row open from the bar (one at a time), shown in the bar above its buttons so it moves
    /// with the keyboard; only when opened, so the writing area stays as large as it can.
    private var openRow: AnyView? {
        let row: AnyView? = if editor.isEditingLink {
            AnyView(LinkRow(editor: editor))
        } else if showsHashtagBar {
            AnyView(hashtagSuggestions)
        } else if showsAskRow {
            AnyView(askRow)
        } else if showsPhotoDrawer, attachedPhotoCount > 0 {
            AnyView(photoBar)
        } else {
            nil
        }
        // A little space between the row and the buttons under it.
        return row.map { row in AnyView(VStack(spacing: 0) { Divider(); row }.padding(.bottom, 8)) }
    }

    /// The photo picker's selection: the library photos only. Camera photos keep their places (and
    /// their share of the limit); newly picked ones go after what's already there.
    private var libraryItems: Binding<[PhotosPickerItem]> {
        Binding {
            photoItems.filter { !cameraItems.contains($0) }
        } set: { picked in
            let kept = photoItems.filter { cameraItems.contains($0) || picked.contains($0) }
            photoItems = kept + picked.filter { !kept.contains($0) }
        }
    }

    private var attachedPhotoCount: Int { photoItems.count + (existingPhotoURL == nil ? 0 : 1) }

    /// The bar's left on a free account: the Photos button is there, and says photos come with PRO.
    private var proPhotosButton: some View {
        Button { explainingProPhotos = true } label: {
            appIcon("slab-images")
                .frame(width: 40, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Photos")
        .accessibilityHint("Part of Dabble Me PRO")
    }

    /// The bar's left: Photos (PRO). With none yet, the library and (where there's one) the camera,
    /// each a tap away; with some it's their stack, which shows or hides the photo row (selected
    /// while it's open).
    @ViewBuilder
    private var photosButton: some View {
        if attachedPhotoCount == 0 {
            HStack(spacing: 2) {
                Button { pickingPhotos = true } label: {
                    appIcon("slab-images")
                        .frame(width: 40, height: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Photos")
                if CameraPicker.isAvailable || showsCameraMenuForTesting {
                    Button { takingPhoto = CameraPicker.isAvailable } label: {
                        appIcon("slab-camera")
                            .frame(width: 40, height: 36)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Take Photo")
                }
            }
        } else {
            photoStack
        }
    }

    /// Add more photos (the photo row's button): from the library, or (where there's a camera) a
    /// menu to take one or choose.
    @ViewBuilder
    private func addPhotos(@ViewBuilder label: () -> some View) -> some View {
        if CameraPicker.isAvailable || showsCameraMenuForTesting {
            Menu {
                Button { takingPhoto = CameraPicker.isAvailable } label: { Label("Take Photo", icon: "camera") }
                Button { pickingPhotos = true } label: { Label("Choose Photos", icon: "slab-images") }
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            Button { pickingPhotos = true } label: { label() }
                .buttonStyle(.plain)
        }
    }

    /// UI tests: `-DabbleDebugCameraMenu YES` shows the menu on the simulator, which has no camera.
    private var showsCameraMenuForTesting: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "DabbleDebugCameraMenu")
        #else
        false
        #endif
    }

    /// The bar's right: Link (PRO; shows or hides the link row), Tags (the hashtag row), then Prompt
    /// (the question mark) at the far edge. Each row button is selected while its row is open; one row at a time.
    private var tagAndLinkButtons: some View {
        HStack(spacing: 6) {
            if model.me?.mayAddLinks == true {
                Button {
                    if editor.isEditingLink { editor.endLink() } else { editor.beginLink() }
                } label: {
                    appIcon("slab-link")
                        .frame(width: 40, height: 36)
                        .background(editor.isEditingLink ? Color.accentColor.opacity(0.22) : .clear, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Link")
                .accessibilityAddTraits(editor.isEditingLink ? .isSelected : [])
            }
            Button {
                showsHashtagBar.toggle()
                if showsHashtagBar {
                    showsPhotoDrawer = false
                    showsAskRow = false
                    editor.endLink()
                    Task { recentTags = (try? await model.recentHashtags()) ?? [] }
                    Task { if allTags.isEmpty { allTags = ((try? await model.allHashtags()) ?? []).map(\.tag) } }
                }
            } label: {
                appIcon("slab-tag")
                    .frame(width: 40, height: 36)
                    .background(showsHashtagBar ? Color.accentColor.opacity(0.22) : .clear, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hashtags")
            .accessibilityAddTraits(showsHashtagBar ? .isSelected : [])
            if canAsk {
                Button {
                    showsAskRow.toggle()
                    if showsAskRow {
                        showsHashtagBar = false
                        showsPhotoDrawer = false
                        editor.endLink()
                        question = nil
                        Task { await ask() }
                    }
                } label: {
                    appIcon("slab-question")
                        .frame(width: 40, height: 36)
                        .background(showsAskRow ? Color.accentColor.opacity(0.22) : .clear, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Prompt")
                .accessibilityHint("Shows a question to write about")
                .accessibilityAddTraits(showsAskRow ? .isSelected : [])
            }
        }
    }

    /// The attached photos as a little stack; tap to show or hide the photo row.
    private var photoStack: some View {
        let thumbs = Array(photoItems.prefix(3))
        return Button {
            showsPhotoDrawer.toggle()
            if showsPhotoDrawer { showsHashtagBar = false; showsAskRow = false; editor.endLink() } // one row at a time
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    if thumbs.count < 3, let existingPhotoURL {
                        AsyncImage(url: existingPhotoURL) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                            .stackedThumbnail(index: 0)
                    }
                    ForEach(Array(thumbs.enumerated()), id: \.offset) { index, item in
                        Group {
                            if let preview = previews[item] { preview.resizable().scaledToFill() } else { Color.secondary.opacity(0.2) }
                        }
                        .stackedThumbnail(index: index + (existingPhotoURL == nil ? 0 : 1))
                    }
                }
                .frame(width: 40, height: 34)
                Text("\(attachedPhotoCount)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(showsPhotoDrawer ? Color.accentColor.opacity(0.22) : .clear, in: .capsule)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photos")
        .accessibilityValue(attachedPhotoCount == 1 ? "1 photo" : "\(attachedPhotoCount) photos")
        .accessibilityAddTraits(showsPhotoDrawer ? .isSelected : [])
        .accessibilityHint(showsPhotoDrawer ? "Hides the photos" : "Shows the photos")
    }

    /// Makes it obvious the app is working (photo uploads can take a while on cellular).
    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(savingMessage)
                    .font(.headline)
                    .monospacedDigit()
                if !photos.isEmpty {
                    Text("Keep the app open until this finishes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
        .accessibilityElement(children: .combine)
    }

    private var savingMessage: String {
        guard let uploadedCount, !photos.isEmpty else { return "Saving…" }
        if uploadedCount >= photos.count { return "Saving entry…" }
        return photos.count == 1 ? "Uploading photo…" : "Uploading photo \(uploadedCount + 1) of \(photos.count)…"
    }

    /// Tags to tap in: Suggest (on-device suggestions for what's written, where Apple Intelligence
    /// is on) first, then its suggestions and the writer's tags that match a word in the entry
    /// (both highlighted), then the most recently used tags. A tag already in the entry isn't
    /// offered again.
    private var hashtagSuggestions: some View {
        let text = editor.plainText
        let inEntry = Set(JournalIntelligence.hashtags(in: text).map { $0.lowercased() })
        var seen = inEntry
        let matching = JournalIntelligence.tags(allTags + recentTags, matchingWordsIn: text)
        let highlighted = Set((suggestedTags + matching).map { $0.lowercased() })
        let tags = (suggestedTags + matching + recentTags).filter { seen.insert($0.lowercased()).inserted }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if JournalIntelligence.canSuggestHashtags(for: model.me) {
                    // The same size while it works: the word stays (hidden) under the spinner.
                    // Not disabled while it works (that greys it out): extra taps are ignored.
                    Button { if !isSuggestingTags { Task { await suggestHashtags() } } } label: {
                        Text("Suggest")
                            .opacity(isSuggestingTags ? 0 : 1)
                            .overlay { if isSuggestingTags { ProgressView().controlSize(.small).tint(.white) } }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Suggest Hashtags")
                }
                ForEach(tags, id: \.self) { tag in
                    Button("#\(tag)") {
                        editor.addHashtag(tag)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(highlighted.contains(tag.lowercased()) ? .accentColor : .secondary)
                    .accessibilityHint("Adds this hashtag to the entry")
                }
                if tags.isEmpty, !isSuggestingTags {
                    Text("Your hashtags will show here.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        // Its own height: a horizontal scroll view would otherwise stretch to share the editor's.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Ask Me

    /// Always, with Apple Intelligence on: before there's much written, the prompt comes from recent
    /// entries (like Today's); after, it's mostly about the draft. Without it, a new entry still
    /// has today's prompt to show.
    private var canAsk: Bool {
        JournalIntelligence.isEnabled(for: model.me) || (isNew && todaysPrompt != nil)
    }

    /// The prompt on Today's card: the one written for today on the device when there is one,
    /// otherwise the day's general prompt.
    private var todaysPrompt: String? {
        guard let today = model.today else { return nil }
        let defaults = UserDefaults.standard
        if JournalIntelligence.isEnabled(for: model.me), defaults.string(forKey: "ai.prompt.day") == today.date,
           let personal = defaults.string(forKey: "ai.prompt.text"), !personal.isEmpty { return personal }
        return today.prompt
    }

    /// One question about the draft (Apple Intelligence, on the device): Insert puts it in the entry.
    /// For another, close the row and open it again.
    private var askRow: some View {
        HStack(alignment: .center, spacing: 10) {
            if isAsking {
                ProgressView().controlSize(.small)
                Text("Generating prompt…")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if let question {
                Text(question)
                    .font(.system(.subheadline, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("AskMeQuestion")
                Button("Insert") {
                    editor.addQuestion(question)
                    self.question = nil
                    showsAskRow = false
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityHint("Adds the question to your entry to answer")
            } else {
                Text(askError ?? "")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .padding(.horizontal)
        .padding(.top, 8)
        .animation(.easeOut(duration: 0.2), value: question)
    }

    private func ask() async {
        guard !isAsking else { return }
        // A new entry with nothing written yet: the prompt Today showed, first, so it can be
        // seen again without leaving the draft. (And the only one without Apple Intelligence.)
        let usesAI = JournalIntelligence.isEnabled(for: model.me)
        if isNew, let todaysPrompt, !usesAI || (editor.isEmpty && !askedQuestions.contains(todaysPrompt)) {
            question = todaysPrompt
            askedQuestions.append(todaysPrompt)
            askError = nil
            return
        }
        isAsking = true
        defer { isAsking = false }
        do {
            let today = model.today?.day ?? JournalDay(localDate: .now)
            if recentForPrompts == nil {
                // Not the entry being edited: it's the draft already.
                let editing: Int? = if case .edit(let entry) = mode { entry.id } else { nil }
                let recent = ((try? await model.recentEntries()) ?? []).filter { $0.id != editing }
                recentForPrompts = JournalIntelligence.dated(recent, today: today)
                curatedPrompts = await model.curatedPrompts()
            }
            let next = try await JournalIntelligence.followUpQuestion(for: editor.plainText, recent: recentForPrompts ?? [],
                                                                      curated: curatedPrompts, today: today, asked: askedQuestions)
            question = next
            askedQuestions.append(next)
            askError = nil
        } catch is CancellationError {
        } catch {
            question = nil
            askError = error.localizedDescription
        }
    }

    private func suggestHashtags() async {
        guard !isSuggestingTags else { return }
        isSuggestingTags = true
        defer { isSuggestingTags = false }
        do {
            let existing = try await model.allHashtags().map(\.tag)
            suggestedTags = try await JournalIntelligence.suggestHashtags(for: editor.plainText, from: existing)
        } catch is CancellationError {
        } catch {
            suggestionError = error.localizedDescription
        }
    }

    /// One compact row: thumbnails, "Add More", and the count (several photos become a collage).
    /// Add more first (while there's room; the picker keeps count), then each photo with its X.
    private var photoBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                if photoItems.count < photoLimit {
                    // The thumbnails' size, in the accent like Suggest.
                    addPhotos {
                        appIcon("slab-images")
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor, in: .rect(cornerRadius: 8))
                    }
                    .accessibilityLabel("Add More Photos")
                }
                if let existingPhotoURL {
                    existingThumbnail(existingPhotoURL)
                }
                ForEach(photoItems, id: \.self) { item in
                    thumbnail(for: item)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The entry's current photo when editing; the X removes it on save.
    private func existingThumbnail(_ url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.12)
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 8))

            Button {
                removesExistingPhoto = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .padding(3)
            }
            .accessibilityLabel("Remove current photo")
            .disabled(isSaving)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current photo")
    }

    @ViewBuilder
    private func thumbnail(for item: PhotosPickerItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let preview = previews[item] {
                    preview.resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.secondary.opacity(0.12)
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 8))

            Button {
                cameraItems.removeAll { $0 == item }
                photoItems.removeAll { $0 == item }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .padding(3) // inside the corner: the photo strip clips anything outside it
            }
            .accessibilityLabel("Remove photo")
            .disabled(isSaving)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected photo")
    }

    #if DEBUG
    /// UI tests and screenshots: `-DabbleDebugComposePhotoURLs "url1,url2"` attaches those images
    /// as if picked (the system photo picker runs out of process, out of a UI test's reach).
    private func attachDebugPhotos() async {
        guard photoItems.isEmpty,
              let raw = UserDefaults.standard.string(forKey: "DabbleDebugComposePhotoURLs") else { return }
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        var items: [PhotosPickerItem] = []
        for (index, string) in raw.split(separator: ",").enumerated() {
            guard let url = URL(string: String(string)),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let photo = try? PhotoPreparer.prepare(data) else { continue }
            let item = PhotosPickerItem(itemIdentifier: "debug-\(index)")
            prepared[item] = photo
            previews[item] = UIImage(data: photo.thumbnail).map(Image.init(uiImage:))
            items.append(item)
        }
        photoItems = items
    }
    #endif

    /// A photo from the camera joins the picked ones, prepared the same way.
    private func addCameraPhoto(_ image: UIImage) async {
        guard photoItems.count < photoLimit else { return }
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        let photo = await Task.detached(priority: .userInitiated) {
            image.jpegData(compressionQuality: 0.95).flatMap { try? PhotoPreparer.prepare($0) }
        }.value
        guard let photo else { error = "The photo couldn't be added."; return }
        let item = PhotosPickerItem(itemIdentifier: "camera-\(UUID().uuidString)")
        prepared[item] = photo
        previews[item] = UIImage(data: photo.thumbnail).map(Image.init(uiImage:))
        cameraItems.append(item)
        photoItems.append(item)
    }

    /// Prepares newly picked photos (downscale, strip location) and forgets removed ones.
    private func preparePhotos() async {
        let current = Set(photoItems)
        cameraItems.removeAll { !current.contains($0) }
        prepared = prepared.filter { current.contains($0.key) }
        previews = previews.filter { current.contains($0.key) }
        let pending = photoItems.filter { prepared[$0] == nil }
        guard !pending.isEmpty else { return }

        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        var failed = 0
        for item in pending {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw PhotoError.unreadable }
                let photo = try await Task.detached(priority: .userInitiated) { try PhotoPreparer.prepare(data) }.value
                if photoItems.contains(item) {
                    prepared[item] = photo
                    previews[item] = UIImage(data: photo.thumbnail).map(Image.init(uiImage:))
                }
            } catch {
                failed += 1
                photoItems.removeAll { $0 == item }
            }
        }
        if failed > 0 {
            error = failed == 1 ? "One photo couldn't be added." : "\(failed) photos couldn't be added."
        }
    }

    // MARK: - Drafts

    /// Editing an entry with formatting the app can't hold (styles, quotes, images in the text…):
    /// it's shown without it, and saving keeps it that way.
    private var isSimplified: Bool {
        if case .edit(let entry) = mode { entry.documentSimplified == true } else { false }
    }

    private var simplifiedBanner: some View {
        Label("Some previous formatting may be lost if you edit.", icon: "slab-triangle-exclamation")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5))
            .accessibilityIdentifier("SimplifiedBanner")
    }

    private var draftBanner: some View {
        HStack(spacing: 12) {
            Label("Restored your unsaved draft.", systemImage: "clock.arrow.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Start Over") {
                editor.replace(with: originalBlocks)
                DraftStore.clear(draftKey)
                restoredDraft = nil
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
    }

    private func scheduleDraftSave() {
        draftSave?.cancel()
        draftSave = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            saveDraftNow()
        }
    }

    /// Discarding is final: nothing still pending (or fired while the sheet closes) saves it again.
    private func discardDraft() {
        isDiscarded = true
        draftSave?.cancel()
        DraftStore.clear(draftKey)
    }

    private func saveDraftNow() {
        guard !isSaving, !isDiscarded, editor.isDirty || restoredDraft != nil else { return }
        let blocks = editor.blocks
        if blocks.isEmpty {
            DraftStore.clear(draftKey)
        } else {
            DraftStore.save(.init(blocks: blocks, date: isNew || movedTo != nil ? JournalDay(localDate: date).iso : nil, savedAt: Date()), key: draftKey)
        }
    }

    private func save(merging: Bool = false) async {
        isSaving = true
        defer { isSaving = false }
        do {
            switch mode {
            case .new:
                uploadedCount = photos.isEmpty ? nil : 0
                defer { uploadedCount = nil }
                let result = try await model.createEntry(day: JournalDay(localDate: date), document: editor.blocks, photos: photos) {
                    uploadedCount = $0
                }
                onSaved(result.entry)
            case .edit(let entry):
                uploadedCount = photos.isEmpty ? nil : 0
                defer { uploadedCount = nil }
                onSaved(try await model.updateEntry(id: entry.id, document: editor.blocks, day: movedTo, merging: merging,
                                                    photos: photos, removeImage: removesExistingPhoto) { uploadedCount = $0 })
            }
            draftSave?.cancel()
            DraftStore.clear(draftKey)
            dismiss()
        } catch let error as APIError where error.code == "date_taken" {
            // That day has an entry: ask before putting the two together.
            mergeQuestion = error.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension View {
    /// One photo in the bar's little stack: fanned slightly, with a light edge.
    func stackedThumbnail(index: Int) -> some View {
        frame(width: 28, height: 28)
            .clipShape(.rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
            .rotationEffect(.degrees(Double(index) * 7 - 7))
            .offset(x: CGFloat(index) * 5 - 5)
    }
}

/// The link row: the address, with Insert (or Update for a link that's there, which can also be
/// removed with the trash, at the far right). Opened from the Link button it takes the keyboard; opened by selecting
/// a link, the selection stays until the address is tapped.
private struct LinkRow: View {
    @Bindable var editor: RichTextEditorModel

    private var canApply: Bool { RichTextEditorModel.normalizedURL(editor.linkText) != nil }

    var body: some View {
        HStack(spacing: 10) {
            // Opened from the Link button, the address takes the keyboard, so typing goes here and
            // not into the entry.
            LinkAddressField(text: $editor.linkText,
                             focusRequest: editor.linkOpenedBySelection ? 0 : editor.linkFocusRequest,
                             onSubmit: apply)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.12), in: .capsule)
            Button(editor.isExistingLink ? "Update" : "Insert", action: apply)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(!canApply)
            if editor.isExistingLink {
                Button {
                    editor.removeLink()
                    editor.focus()
                } label: {
                    appIcon("slab-trash")
                        .foregroundStyle(Color.deleteRed)
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove Link")
            }
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func apply() {
        guard canApply else { return }
        editor.applyLink()
        editor.focus()
    }
}

/// The link row's address field. A UIKit field, asked directly to take the keyboard: the row is
/// in the bar over the keyboard, where SwiftUI's own focus could report the field focused while
/// the keyboard still typed into the entry.
private struct LinkAddressField: UIViewRepresentable {
    @Binding var text: String
    /// Changes (to anything but 0) each time the field should take the keyboard.
    let focusRequest: Int
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> Field {
        let field = Field()
        field.placeholder = "https://"
        field.font = .preferredFont(forTextStyle: .subheadline)
        field.adjustsFontForContentSizeCategory = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        // The ordinary keyboard, not the URL one: swapping keyboards as the field took over could
        // leave the entry with the typing while the field looked ready for it.
        field.keyboardType = .default
        field.returnKeyType = .done
        field.accessibilityLabel = "Link address"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        guard focusRequest != context.coordinator.focusRequest else { return }
        context.coordinator.focusRequest = focusRequest
        if focusRequest != 0 { field.takeKeyboard() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Field, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: uiView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LinkAddressField
        var focusRequest = 0

        init(_ parent: LinkAddressField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }

    /// Takes the keyboard once it can: the row has only just been put in the bar when it's asked,
    /// so it tries again when it joins the window and for a moment after, until it has it.
    final class Field: UITextField {
        private var wantsKeyboard = false
        private var retry: Task<Void, Never>?

        func takeKeyboard() {
            wantsKeyboard = true
            retry?.cancel()
            retry = Task { [weak self] in
                for _ in 0..<20 {
                    guard let self, self.wantsKeyboard, !Task.isCancelled else { return }
                    self.takeKeyboardIfWanted()
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            takeKeyboardIfWanted()
        }

        private func takeKeyboardIfWanted() {
            guard wantsKeyboard, window != nil else { return }
            if isFirstResponder || becomeFirstResponder() { wantsKeyboard = false }
        }
    }
}

/// The camera, for one photo.
private struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
