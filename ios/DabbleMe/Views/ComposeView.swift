import AVFoundation
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
    @State private var choosingDate = false
    @State private var heldPhotoStack = false
    /// The lightbulb row's content, as tall as it is: the row is that tall, up to `askRowMaxHeight`,
    /// and scrolls past it. Nothing until it's measured, each time the row opens: a height kept
    /// from the last time would be an empty band over the entry while this one's content (its
    /// question, the day's events) is still coming in.
    @State private var askRowHeight: CGFloat = 0
    /// The row's heading, which stays put over what scrolls.
    @State private var askHeadingHeight: CGFloat = 30
    private static let askRowMaxHeight: CGFloat = 236
    /// The entry's day has events on the calendar (they're listed under the prompt).
    @State private var hasAgenda = false
    /// Bumped when the calendar row's contents change, so the bar over the keyboard resizes.
    @State private var calendarRowKey = 0
    /// The tag icon was held (so the tap that ends the hold doesn't also open its row), and
    /// what that did, said for a moment over the entry: "Tagged #Leo and #Sam".
    @State private var heldTagIcon = false
    /// Bold was held: the bar shows the format buttons with nothing selected, for what's typed
    /// next, until the cursor's put somewhere else.
    @State private var showsFormatBar = false
    @State private var boldHeldAt: Date?
    @State private var autoTagNotice: String?
    @State private var photoItems: [PhotosPickerItem] = []
    /// Prepared photos keyed by picker item, so re-selecting doesn't redo the work.
    @State private var prepared: [PhotosPickerItem: PreparedPhoto] = [:]
    /// Decoded once from each photo's small thumbnail, never from the full-size data.
    @State private var previews: [PhotosPickerItem: Image] = [:]
    @State private var isLoadingPhotos = false
    @State private var isSaving = false
    @State private var uploadedCount: Int?
    @State private var error: String?
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
    @State private var pickingPhotos = false
    /// A free account tapped Photos: a note that they're part of PRO.
    @State private var explainingProPhotos = false
    /// A one-time tip about a touch-and-hold shortcut (`showTipOnce`).
    @State private var tip: String?
    @State private var takingPhoto = false
    /// Photos taken with the camera: they ride along in `photoItems` under made-up identifiers,
    /// which the photo picker doesn't know, so the picker works on `libraryItems` instead.
    @State private var cameraItems: [PhotosPickerItem] = []
    @State private var removesExistingPhoto = false
    /// Each added photo's name in the draft's photo folder (given when the draft first keeps it).
    @State private var draftPhotoNames: [PhotosPickerItem: String] = [:]
    /// The restored draft's photos are being put back, or have been (once: they're read from disk).
    @State private var restoredDraftPhotos = false
    /// They're back: until then the draft isn't saved over, which would leave them out.
    @State private var draftPhotosLoaded = false
    /// A draft of this has been kept, so a change back to nothing (a photo added, then taken
    /// out) is kept too, rather than leaving the draft as it was.
    @State private var keptDraft = false
    @Environment(\.scenePhase) private var scenePhase
    private let draftKey: String
    /// Opened for a day of its own, which today's date doesn't then replace.
    private let startsOnDay: Bool
    private let originalBlocks: [DocumentBlock]
    /// The writer's template (Settings → Entry Template), as it was when this opened.
    private let template: [DocumentRun]
    /// A new entry set to start with the template.
    private let startsWithTemplate: Bool
    /// The editor holds the template and nothing else yet (a new entry set to start with it):
    /// there's nothing to save until something's written.
    @State private var isUntouchedTemplate: Bool
    /// The lightbulb button was held (so the tap that ends the hold doesn't also open its row).
    @State private var heldAskIcon = false

    /// `day`: a new entry for that day (Stats' grid), not today. `withTemplate`: a new entry
    /// that starts from the writer's template whatever the setting says (a held Write button).
    init(mode: Mode, day: JournalDay? = nil, withTemplate: Bool = false, onSaved: @escaping (EntryDetail) -> Void = { _ in }) {
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
        // A new entry set to start with the template has it from the outset, and again after
        // Start Over. A draft, as ever, comes first.
        let template = EntryTemplate.runs
        self.template = template
        let startsWithTemplate = entry == nil && !template.isEmpty && (EntryTemplate.addsToNewEntries || withTemplate)
        self.startsWithTemplate = startsWithTemplate
        originalBlocks = original
        _isUntouchedTemplate = State(initialValue: startsWithTemplate && draft == nil)
        _restoredDraft = State(initialValue: draft)
        _removesExistingPhoto = State(initialValue: entry != nil && draft?.removesPhoto == true)
        if let date = day ?? draft?.date.flatMap(JournalDay.init) ?? entry?.day { _date = State(initialValue: date.localDate) }
        _editor = State(initialValue: draft == nil && startsWithTemplate ? RichTextEditorModel(typed: template)
            : draft?.typed.map { RichTextEditorModel(typed: $0, atFirstBlank: false) } ?? RichTextEditorModel(blocks: draft?.blocks ?? originalBlocks))
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
        return isNew ? ((!editor.isEmpty && !isUntouchedTemplate) || !photos.isEmpty)
            : (!editor.isEmpty && (editor.isDirty || restoredDraft != nil || !photos.isEmpty || removesExistingPhoto || movedTo != nil))
    }

    /// There's something to keep as a draft: words, photos, or a removed photo.
    private var canSaveDraft: Bool {
        (!editor.isEmpty || !photoItems.isEmpty || removesExistingPhoto)
            && (editor.isDirty || restoredDraft != nil || !photoItems.isEmpty || removesExistingPhoto)
    }

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
                // The bar's icons are olive, not black: there are a lot of them, next to the writing.
                RichTextEditor(model: editor,
                               leading: isFormattingSelection ? linkButtons.map { AnyView($0.foregroundStyle(.tint)) }
                                   : AnyView((model.me?.canAddPhotos == true ? AnyView(photosButton) : AnyView(proPhotosButton)).foregroundStyle(.tint)),
                               trailing: AnyView((isFormattingSelection ? AnyView(selectionButtons) : AnyView(tagAndLinkButtons)).foregroundStyle(.tint)),
                               trailingEnd: isFormattingSelection ? AnyView(closeFormatsButton.foregroundStyle(.tint)) : nil,
                               barKey: "\(isFormattingSelection)|\(showsFormatBar)|\(editor.isExistingLink)|\(visitURL != nil)|\(editor.hasSelection)|\(editor.isBold)|\(editor.isItalic)|\(editor.isUnderlined)|\(model.me?.mayAddLinks == true)|\(CameraPicker.isAvailable)|\(calendarRowKey)|\(attachedPhotoCount)|\(showsPhotoDrawer)|\(previews.count)|\(existingPhotoURL?.absoluteString ?? "")|\(showsHashtagBar)|\(showsAskRow)|\(canAsk)|\(editor.isEditingLink)",
                               row: openRow)
                    // Low in the page, over the bar: clear of the entry's first lines.
                    .overlay(alignment: .bottom) {
                        if let autoTagNotice {
                            Text(autoTagNotice)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: .capsule)
                                .padding(.bottom, 68)
                                .padding(.horizontal, 24)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if editor.isEmpty {
                            // About the day being written: today, yesterday, or another by name.
                            Text(JournalDay(localDate: date).writingQuestion(today: model.today?.day ?? JournalDay(localDate: .now)))
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
                    // With something to lose, Cancel drops down Save Draft and Discard, no
                    // question around them: a tap outside it is Keep Writing.
                    if hasChanges {
                        Menu("Cancel") {
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
                        }
                    } else {
                        Button("Cancel") {
                            discardDraft()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        TypingDots(size: .small)
                            .accessibilityLabel("Saving")
                            .padding(.horizontal, 8)
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(hasChanges || isSaving)
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
            // Held open, the format buttons go when the cursor's put somewhere else, and a
            // selection (which shows them itself) takes over from the hold.
            .onChange(of: editor.caretMoves) { showsFormatBar = false }
            .onChange(of: editor.hasSelection) { showsFormatBar = false }
            .onChange(of: editor.isEditingLink) { _, editing in
                // One row at a time (the link row also opens by selecting a link).
                if editing { showsHashtagBar = false; showsAskRow = false; showsPhotoDrawer = false }
            }
            .photosPicker(isPresented: $pickingPhotos, selection: libraryItems, maxSelectionCount: photoLimit - cameraItems.count,
                          selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
            .onChange(of: photoItems) { old, new in
                // Newly added photos go into the stack; the drawer closes to keep room for writing.
                if new.count > old.count { showsPhotoDrawer = false }
                Task { await preparePhotos() }
            }
            #if DEBUG
            .task { await attachDebugPhotos() }
            #endif
            // A hashtag's being typed: the writer's tags, to offer the ones that start that way
            // (fetched the first time, unless the hashtag row has brought them already).
            .onChange(of: editor.typedHashtag != nil) { _, typing in
                guard typing else { return }
                if recentTags.isEmpty { Task { recentTags = (try? await model.recentHashtags()) ?? [] } }
                if allTags.isEmpty { Task { allTags = ((try? await model.allHashtags()) ?? []).map(\.tag) } }
            }
            .alert("Tip", isPresented: .present($tip)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(tip ?? "")
            }
            .alert("Photos are a PRO feature", isPresented: $explainingProPhotos) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("With Dabble Me PRO you can add up to \(photoLimit) photos to an entry.")
            }
            .onChange(of: editor.revision) {
                isUntouchedTemplate = false
                scheduleDraftSave()
            }
            .onChange(of: date) { scheduleDraftSave() }
            .onChange(of: removesExistingPhoto) { scheduleDraftSave() }
            .task { await restoreDraftPhotos() }
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
    /// It opens a calendar under it, which marks the days that already have an entry.
    private var dateTitle: some View {
        Button {
            // The keyboard down while it's open, so the whole month fits; back up after.
            editor.unfocus()
            choosingDate = true
        } label: {
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.tint.opacity(0.12), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Entry date")
        .accessibilityValue(date.formatted(date: .complete, time: .omitted))
        .popover(isPresented: $choosingDate) { EntryDatePopover(date: $date) }
        .onChange(of: choosingDate) { _, open in if !open { editor.focus() } }
    }

    /// The entry's photos: its current one (editing) and those being added.
    /// The row open from the bar (one at a time), shown in the bar above its buttons so it moves
    /// with the keyboard; only when opened, so the writing area stays as large as it can.
    private var openRow: AnyView? {
        let row: AnyView? = if editor.isEditingLink {
            AnyView(LinkRow(editor: editor))
        } else if let typed = editor.typedHashtag, !hashtagCompletions(for: typed).isEmpty {
            // A hashtag being typed: the writer's tags that start that way, whatever row was open.
            AnyView(hashtagCompletionRow(hashtagCompletions(for: typed)))
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

    /// With words selected (or Bold held), the bar is the formats' alone: Bold, Italic and
    /// Underline on the right, each lit while all the words have it; Link on the left
    /// (`linkButtons`). Photos, hashtags and prompts aren't for a selection, and are out of the
    /// way until it's let go.
    private var selectionButtons: some View {
        HStack(spacing: 6) {
            formatButton("Bold", .bold, isOn: editor.isBold, toggle: toggleBold)
            formatButton("Italic", .italic, isOn: editor.isItalic) { editor.toggleItalic() }
            formatButton("Underline", .underline, isOn: editor.isUnderlined) { editor.toggleUnderline() }
        }
        // (While the link's address is being typed the words aren't the keyboard's: these wait.)
        .disabled(editor.isEditingLink && !editor.hasSelection)
        .opacity(editor.isEditingLink && !editor.hasSelection ? 0.35 : 1)
    }

    /// The format bar's left, where Photos is otherwise: Link (PRO; shows or hides the link
    /// row) and, for a link that's there, Visit (the external-link symbol), which opens it.
    /// (The trash that removes it is at the far left of the link row, away from Update.)
    private var linkButtons: AnyView? {
        guard model.me?.mayAddLinks == true else { return nil }
        return AnyView(HStack(spacing: 6) {
            Button {
                if editor.isEditingLink { editor.endLink() } else { editor.beginLink() }
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 36)
                    .background(editor.isEditingLink ? Color.accentColor.opacity(0.22) : .clear, in: .capsule)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Link")
            .accessibilityAddTraits(editor.isEditingLink ? .isSelected : [])
            if editor.isEditingLink, editor.isExistingLink {
                Button {
                    if let visitURL { UIApplication.shared.open(visitURL) }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 40, height: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(visitURL == nil)
                .opacity(visitURL == nil ? 0.35 : 1)
                .accessibilityLabel("Visit Link")
            }
        })
    }

    /// The format bar's way back to the usual one, in a group of its own at the far right: it
    /// lets go of the selection (the cursor stays at its end), closes the link row and the
    /// held-open formats. Without it, the only way back from a held Bold was a tap in the text.
    private var closeFormatsButton: some View {
        Button {
            showsFormatBar = false
            editor.leaveFormatting()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close Formatting")
    }

    /// Where Visit goes: the address in the link row, as it stands.
    private var visitURL: URL? {
        editor.isEditingLink && editor.isExistingLink ? RichTextEditorModel.normalizedURL(editor.linkText) : nil
    }

    /// One of the bar's format buttons (see `FormatButton`).
    private func formatButton(_ name: String, _ letter: FormatLetter, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        FormatButton(name: name, letter: letter, isOn: isOn, toggle: toggle)
    }

    /// Bold's tap, but not the one that ends the hold that opened the format buttons.
    private func toggleBold() {
        if let boldHeldAt, Date.now.timeIntervalSince(boldHeldAt) < 0.8 { return }
        editor.toggleBold()
    }

    /// Words are selected in the entry, a link's address is being typed for some, or Bold was
    /// held: the bar shows `linkButtons` and `selectionButtons`, and nothing else.
    private var isFormattingSelection: Bool { editor.hasSelection || editor.isEditingLink || showsFormatBar }

    /// The bar's right, with nothing selected: Bold (for what's typed next), Tags (the hashtag row), then Prompt
    /// (the lightbulb) at the far edge. Each row button is selected while its row is open; one row at a time.
    private var tagAndLinkButtons: some View {
        HStack(spacing: 6) {
            // Bold, always: for what's typed next (lit while that's bold; a tap turns it off).
            formatButton("Bold", .bold, isOn: editor.isBold, toggle: toggleBold)
                // Held: the other formats, to start typing in italics or underlined.
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    boldHeldAt = .now
                    HoldHaptic.play()
                    showsHashtagBar = false
                    showsAskRow = false
                    showsPhotoDrawer = false
                    showsFormatBar = true
                })
                .accessibilityAction(named: "Show Italic and Underline") { showsFormatBar = true }
            Button {
                // Not the tap that ends a hold.
                if heldTagIcon { heldTagIcon = false; return }
                showsHashtagBar.toggle()
                if showsHashtagBar {
                    showsPhotoDrawer = false
                    showsAskRow = false
                    editor.endLink()
                    Task { recentTags = (try? await model.recentHashtags()) ?? [] }
                    Task { if allTags.isEmpty { allTags = ((try? await model.allHashtags()) ?? []).map(\.tag) } }
                    Task { await suggestHashtags() }
                }
            } label: {
                appIcon("slab-tag")
                    .frame(width: 40, height: 36)
                    .background(showsHashtagBar ? Color.accentColor.opacity(0.22) : .clear, in: .capsule)
            }
            .buttonStyle(.plain)
            // Held: tags the entry's own words with the hashtags they match, in one go.
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                heldTagIcon = true
                HoldHaptic.play()
                Task { await tagMatchingWords() }
            })
            .accessibilityLabel("Hashtags")
            .accessibilityAddTraits(showsHashtagBar ? .isSelected : [])
            .accessibilityAction(named: "Tag Matching Words") { Task { await tagMatchingWords() } }
            // "What should I write about?": what was on the calendar that day (for everyone)
            // and, where there's one to be had, a question to answer.
            Button {
                // Not the tap that ends a hold.
                if heldAskIcon { heldAskIcon = false; return }
                showsAskRow.toggle()
                if showsAskRow {
                    askRowHeight = 0
                    hasAgenda = false
                    showsHashtagBar = false
                    showsPhotoDrawer = false
                    editor.endLink()
                    question = nil
                    askError = nil
                    // With a template to offer, a prompt is written when it's asked for.
                    if canAsk, !offersTemplate { Task { await ask() } }
                }
            } label: {
                appIcon("slab-lightbulb")
                    .frame(width: 40, height: 36)
                    .background(showsAskRow ? Color.accentColor.opacity(0.22) : .clear, in: .capsule)
            }
            .buttonStyle(.plain)
            // Held: the template goes straight in.
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard !template.isEmpty else { return }
                heldAskIcon = true
                HoldHaptic.play()
                useTemplate()
            })
            .accessibilityLabel("Prompt")
            .accessibilityHint("Shows what was on your calendar that day and a question to write about")
            .accessibilityAddTraits(showsAskRow ? .isSelected : [])
            .accessibilityActions {
                if !template.isEmpty { Button("Use Template") { useTemplate() } }
            }
        }
    }

    /// The attached photos as a little stack; tap to show or hide the photo row. Held, it goes
    /// straight to the library to choose more (no menu on the way).
    private var photoStack: some View {
        let thumbs = Array(photoItems.prefix(3))
        return Button {
            // Not the tap that ends a hold.
            if heldPhotoStack { heldPhotoStack = false; return }
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
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            heldPhotoStack = true
            HoldHaptic.play()
            pickingPhotos = true
        })
        .onChange(of: pickingPhotos) { _, picking in if !picking { heldPhotoStack = false } }
        .accessibilityLabel("Photos")
        .accessibilityValue(attachedPhotoCount == 1 ? "1 photo" : "\(attachedPhotoCount) photos")
        .accessibilityAddTraits(showsPhotoDrawer ? .isSelected : [])
        .accessibilityHint(showsPhotoDrawer ? "Hides the photos" : "Shows the photos")
        .accessibilityAction(named: "Choose Photos") { pickingPhotos = true }
    }

    /// Makes it obvious the app is working (photo uploads can take a while on cellular).
    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                TypingDots(size: .large)
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

    /// Tags to tap in: on-device suggestions for what's written (where Apple Intelligence is on;
    /// they come by themselves as the row opens) and the writer's tags that match a word in the
    /// entry (both highlighted), then the most recently used tags. A tag already in the entry
    /// isn't offered again.
    private var hashtagSuggestions: some View {
        let text = editor.plainText
        var seen = Set(JournalIntelligence.hashtags(in: text).map { $0.lowercased() })
        // In the order they're known: the writer's own tags that are words in the entry (there
        // at once), then the ones suggested on the device (which take a moment), then the
        // recent ones. Each kind keeps its place, so the first don't move when the next arrive.
        let matched = matchedTags
        seen.formUnion(matched.map { $0.lowercased() })
        let suggested = suggestedTags.filter { seen.insert($0.lowercased()).inserted }
        let recent = recentTags.filter { seen.insert($0.lowercased()).inserted }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                // All of the matched ones in one go: only while there are some.
                if !matched.isEmpty {
                    rowButton("Auto Tag") {
                        Task { await tagMatchingWords() }
                        showTipOnce("tag", "Next time, touch and hold the tag button to auto tag the words that match your hashtags straight away.")
                    }
                    .accessibilityHint("Tags the words in the entry that match your hashtags")
                }
                ForEach(matched, id: \.self) { hashtagPill($0, highlighted: true) }
                // Where the suggestions will go, while they're looked for.
                if isSuggestingTags {
                    TypingDots(size: .small)
                        .frame(height: 30)
                        .accessibilityLabel("Suggesting hashtags")
                }
                ForEach(suggested, id: \.self) { hashtagPill($0, highlighted: true) }
                ForEach(recent, id: \.self) { hashtagPill($0, highlighted: false) }
                if matched.isEmpty, suggested.isEmpty, recent.isEmpty, !isSuggestingTags {
                    Text("Your hashtags will show here.")
                        .foregroundStyle(.secondary)
                        .frame(height: 30)
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

    /// The writer's hashtags that start with what's being typed after a "#" ("#hik": hiking,
    /// Hike), the recently used first. Not the one typed out in full already, and none when
    /// nothing of theirs starts that way: it's a new tag, and the row stays out of its way.
    private func hashtagCompletions(for typed: String) -> [String] {
        Self.hashtagCompletions(for: typed, from: recentTags + allTags)
    }

    static func hashtagCompletions(for typed: String, from tags: [String], limit: Int = 20) -> [String] {
        let prefix = typed.lowercased()
        var seen: Set<String> = [prefix]
        return Array(tags.filter { $0.lowercased().hasPrefix(prefix) && seen.insert($0.lowercased()).inserted }.prefix(limit))
    }

    /// Shown by itself while a hashtag is being typed: a tap finishes it.
    private func hashtagCompletionRow(_ tags: [String]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Button("#\(tag)") { editor.completeHashtag(tag) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(.accentColor)
                        .accessibilityHint("Finishes the hashtag you're typing")
                }
            }
            .font(.subheadline)
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("HashtagCompletions")
    }

    private func hashtagPill(_ tag: String, highlighted: Bool) -> some View {
        Button("#\(tag)") {
            editor.addHashtag(tag)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(highlighted ? .accentColor : .secondary)
        .accessibilityHint("Adds this hashtag to the entry")
    }

    /// The writer's own hashtags that are words in the entry and aren't tagged in it yet: what
    /// "Auto Tag" and the held tag button tag.
    private var matchedTags: [String] {
        let text = editor.plainText
        var seen = Set(JournalIntelligence.hashtags(in: text).map { $0.lowercased() })
        return JournalIntelligence.tags(allTags + recentTags, matchingWordsIn: text).filter { seen.insert($0.lowercased()).inserted }
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
        // Its heading stays put, flush under the bar's line; what's under it (the question, then
        // the day's events) is the part that scrolls when there's more than fits.
        VStack(alignment: .leading, spacing: 0) {
            Text("Writing ideas")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tint)
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { askHeadingHeight = $0 }
            askRowContent
        }
    }

    private var askRowContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if canAsk { askLine } else if offersTemplate { templateLine }
                CalendarRow(day: date, hidesWhenEmpty: canAsk || offersTemplate, changed: { hasEvents in
                    hasAgenda = hasEvents
                    calendarRowKey += 1
                }) { event in
                    editor.addQuestion(event.title)
                    showsAskRow = false
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { askRowHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        // (A busy day runs past the row's foot: its scroll bar shows for a moment, to say so.)
        .scrollIndicatorsFlash(onAppear: true)
        .frame(height: min(max(askRowHeight, 1), max(Self.askRowMaxHeight - askHeadingHeight, 44)))
    }

    private func insertQuestion() {
        guard let question, !isAsking else { return }
        editor.addQuestion(question)
        self.question = nil
        showsAskRow = false
    }

    /// The template alone, where there's no prompt to be had (an entry being edited, without
    /// Apple Intelligence).
    private var templateLine: some View {
        HStack(spacing: 12) {
            Text("Your template")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            useTemplateButton
        }
        .padding(.horizontal)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    /// The lightbulb row offers the template (there is one, and this entry didn't start with
    /// it): a prompt is then written only when it's asked for.
    private var offersTemplate: Bool { !template.isEmpty && !startsWithTemplate }

    private func useTemplate() {
        editor.addTemplate(template)
        showsAskRow = false
    }

    /// "Use Template", at the right of the lightbulb row until a prompt's been asked for. The
    /// first time it's used, a word about the quicker way.
    private var useTemplateButton: some View {
        rowButton("Use Template") {
            useTemplate()
            showTipOnce("lightbulb", "Next time, touch and hold the lightbulb button to add your template straight away.")
        }
    }

    /// A small filled button at the right of a row over the keyboard ("Use Template", "Insert").
    private func rowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color("OnAccent"))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.tint, in: .capsule)
            .buttonStyle(.plain)
    }

    /// A tip shown the first time a button is used that has a touch-and-hold shortcut, and not again.
    private func showTipOnce(_ name: String, _ words: String) {
        let key = "tips.shown.\(name)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        tip = words
    }

    /// The question, set like the events under it but from the left edge: a tap on the row puts
    /// it in the entry. (The row's heading, "Writing ideas", is over it and the events alike.)
    private var askLine: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if isAsking {
                    TypingDots(size: .small)
                    Text("Generating prompt…")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else if let question {
                    Text(question)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("AskMeQuestion")
                        // (A tap on it, VoiceOver's too, is the row's.)
                        .accessibilityHint("Adds the question to your entry to answer")
                    appIcon("slab-plus")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                } else if offersTemplate, askError == nil {
                    // (A tap on it, VoiceOver's too, is the row's.)
                    Text(JournalIntelligence.isEnabled(for: model.me) ? "Tap to generate prompt" : "Tap for today's prompt")
                        .fontWeight(.medium)
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isButton)
                    useTemplateButton
                } else {
                    Text(askError ?? "")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.subheadline)
            // As tall as what it holds: a line while the question's being written, then the
            // question's own two or three. The row grows upward for it (it sits on the bar), so
            // the events under it stay where they are.
            .contentShape(.rect)
            .onTapGesture {
                if question != nil {
                    insertQuestion()
                } else if offersTemplate, !isAsking {
                    Task { await ask() }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, hasAgenda ? 6 : 0)
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

    /// The tag icon held, or the hashtag row's "Auto Tag": every hashtag the writer has used
    /// that's a word in the entry gets its "#" there ("Dinner with Leo" → "Dinner with #Leo").
    /// Only their own tags and the entry's own words: nothing's suggested, made up or added at
    /// the end.
    private func tagMatchingWords() async {
        if allTags.isEmpty { allTags = ((try? await model.allHashtags()) ?? []).map(\.tag) }
        let text = editor.plainText
        let inEntry = Set(JournalIntelligence.hashtags(in: text).map { $0.lowercased() })
        // (With the recent ones, as the row matches them: the list of all may still be on its way.)
        let matching = JournalIntelligence.tags(allTags + recentTags, matchingWordsIn: text).filter { !inEntry.contains($0.lowercased()) }
        let tagged = editor.tagWords(matching: matching)
        let notice = tagged.isEmpty ? "No words match your hashtags"
                                    : "Tagged " + ListFormatter.localizedString(byJoining: tagged.map { "#\($0)" })
        withAnimation(.easeOut(duration: 0.15)) { autoTagNotice = notice }
        UIAccessibility.post(notification: .announcement, argument: notice)
        try? await Task.sleep(for: .seconds(2.5))
        if autoTagNotice == notice { withAnimation(.easeOut(duration: 0.3)) { autoTagNotice = nil } }
    }

    /// Suggestions for what's written so far (on the device, where Apple Intelligence is on),
    /// each time the hashtag row opens. Quietly: with none that fit, or none to be had, the row
    /// just has the recent hashtags.
    private func suggestHashtags() async {
        let text = editor.plainText
        guard JournalIntelligence.canSuggestHashtags(for: model.me), !isSuggestingTags,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSuggestingTags = true
        defer { isSuggestingTags = false }
        guard let existing = try? await model.allHashtags().map(\.tag),
              let suggested = try? await JournalIntelligence.suggestHashtags(for: text, from: existing, firstName: model.me?.firstName) else { return }
        suggestedTags = suggested
    }

    /// One compact row: thumbnails, "Add More", and the count (several photos become a collage).
    /// Add more first (while there's room; the picker keeps count), then each photo with its X.
    private var photoBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                if photoItems.count < photoLimit {
                    // The thumbnails' size, in the accent.
                    addPhotos {
                        appIcon("slab-images")
                            .foregroundStyle(Color("OnAccent"))
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
                        TypingDots(size: .small)
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
        draftPhotoNames = draftPhotoNames.filter { current.contains($0.key) }
        // (A photo added or taken away is a change to the draft, as words are.)
        defer { scheduleDraftSave() }
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
                if startsWithTemplate { editor.replace(withTyped: template) } else { editor.replace(with: originalBlocks) }
                // The draft's photos go with it (ones added since stay), and a removed photo's back.
                photoItems.removeAll { $0.itemIdentifier?.hasPrefix("draft-") == true }
                removesExistingPhoto = false
                DraftStore.clear(draftKey)
                restoredDraft = nil
                isUntouchedTemplate = startsWithTemplate
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
        guard !isSaving, !isDiscarded,
              editor.isDirty || restoredDraft != nil || keptDraft || !photoItems.isEmpty || removesExistingPhoto,
              restoredDraft?.photos?.isEmpty != false || draftPhotosLoaded else { return }
        keptDraft = true
        let blocks = editor.blocks
        // The photos ready so far (one still being prepared joins the draft once it is).
        var named: [(name: String, photo: PreparedPhoto)] = []
        for item in photoItems {
            guard let photo = prepared[item] else { continue }
            let name = draftPhotoNames[item] ?? UUID().uuidString
            draftPhotoNames[item] = name
            named.append((name, photo))
        }
        if blocks.isEmpty, named.isEmpty, !removesExistingPhoto {
            DraftStore.clear(draftKey)
        } else {
            DraftStore.savePhotos(named, key: draftKey)
            DraftStore.save(.init(blocks: blocks, typed: editor.typedRuns, date: isNew || movedTo != nil ? JournalDay(localDate: date).iso : nil,
                                  savedAt: Date(), photos: named.isEmpty ? nil : named.map(\.name),
                                  removesPhoto: removesExistingPhoto ? true : nil), key: draftKey)
        }
    }

    /// A restored draft's photos, back in the stack as they were: read from disk once the
    /// composer's open (not while it's being built), under made-up identifiers like the camera's.
    private func restoreDraftPhotos() async {
        guard !restoredDraftPhotos, let names = restoredDraft?.photos, !names.isEmpty else { return }
        restoredDraftPhotos = true
        let key = draftKey
        let loaded = await Task.detached(priority: .userInitiated) { DraftStore.loadPhotos(names, key: key) }.value
        defer { draftPhotosLoaded = true }
        var items: [PhotosPickerItem] = []
        for (name, photo) in loaded.prefix(photoLimit) {
            let item = PhotosPickerItem(itemIdentifier: "draft-\(name)")
            // Prepared before it joins the stack, so it's never sent to the photo library to load.
            prepared[item] = photo
            previews[item] = UIImage(data: photo.thumbnail).map(Image.init(uiImage:))
            draftPhotoNames[item] = name
            items.append(item)
        }
        guard !items.isEmpty else { return }
        cameraItems.append(contentsOf: items)
        photoItems = items + photoItems
    }

    private func save(merging: Bool = false) async {
        // (Not twice: a second tap while the first is still at work.)
        guard !isSaving else { return }
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

/// The link row: the address, with Insert (or Update for a link that's there, and the trash
/// that removes it at the far left, the other end from Update; Visit is in the bar below, on the left). Opened from the Link button it takes the keyboard; opened by selecting
/// a link, the selection stays until the address is tapped.
/// The composer's calendar row: what was on the phone's calendar on the entry's day, each a tap
/// away from being a heading in the entry to write under. iOS asks for the calendar the first
/// time it's opened; without it, the row says how to allow it. It scrolls with the question
/// over it, as one section.
private struct CalendarRow: View {
    let day: Date
    /// With a question over it, a day with nothing on it shows nothing here.
    var hidesWhenEmpty = false
    /// The day's been read (the row's height may have changed): whether it has events to list.
    let changed: (Bool) -> Void
    let pick: (DayEvent) -> Void
    @State private var access = DayCalendar.access
    @State private var events: [DayEvent]?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            // With a question under it there's no need to say there's nothing here: a day
            // with nothing on it, or a calendar that isn't allowed, shows nothing. (That can
            // be allowed in Settings → Calendars.) While the day's still being read, nothing
            // either way.
            if (hidesWhenEmpty && (access == .denied || (access == .allowed && events?.isEmpty == true)))
                || (access == .allowed && events == nil) {
                Color.clear.frame(height: 0)
            } else {
                section
            }
        }
        // (On the two together: the day's read once, whichever is showing.)
        .task(id: day) { await load() }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Titled only while the calendar isn't allowed, over the line that says how to allow
            // it. Over the day's events the title says nothing they don't.
            if access != .allowed {
                Text("On your calendar")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.tint)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            switch access {
            case .denied:
                HStack(spacing: 10) {
                    Text("Allow access to your calendar to see events for this day.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                .font(.subheadline)
                .padding(.vertical, 6)
            case .notAsked:
                ProgressView().controlSize(.small).padding(.vertical, 10)
            case .allowed:
                if let events, events.isEmpty {
                    // (Only when this row is all the lightbulb button has to show: an empty panel
                    // would look broken.)
                    Text("Nothing on your calendar this day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else if let events {
                    list(events)
                }
            }
        }
        .padding(.horizontal)
        // Close under the question; with none over it, the events start right at the row's top.
        .padding(.top, hidesWhenEmpty ? 4 : (access == .allowed && events?.isEmpty == false ? 0 : 10))
        .padding(.bottom, 2)
    }

    private func load() async {
        if access == .notAsked {
            _ = await DayCalendar.requestAccess()
            access = DayCalendar.access
        }
        events = DayCalendar.events(on: day)
        changed(access == .allowed && events?.isEmpty == false)
    }

    /// The width of the events' time column.
    static let timeColumn: CGFloat = 72

    /// As many of the day's events as are worth offering: a few to pick from, not the whole day.
    static let eventLimit = 3

    private func list(_ all: [DayEvent]) -> some View {
        let events = Array(all.prefix(Self.eventLimit))
        return VStack(spacing: 0) {
            // Under a question: a line between it and the first event.
            if hidesWhenEmpty { Divider() }
            ForEach(events) { event in
                Button { pick(event) } label: {
                    HStack(spacing: 12) {
                        Text(event.time)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: Self.timeColumn, alignment: .leading)
                        Text(event.title)
                            .font(.system(.subheadline, design: .serif))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        appIcon("slab-plus")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 9)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(event.title), \(event.time)")
                .accessibilityHint("Adds it to your entry as a heading")
                if event.id != events.last?.id { Divider() }
            }
        }
    }
}

private struct LinkRow: View {
    @Bindable var editor: RichTextEditorModel

    private var canApply: Bool { RichTextEditorModel.normalizedURL(editor.linkText) != nil }

    var body: some View {
        HStack(spacing: 10) {
            // A link that's there can be removed: at the row's far end from Update, so a thumb
            // going for Update doesn't land on it.
            if editor.isExistingLink {
                Button {
                    editor.removeLink()
                    editor.focus()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.deleteRed)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove Link")
            }
            // Opened from the Link button, the address takes the keyboard, so typing goes here and
            // not into the entry.
            LinkAddressField(text: $editor.linkText,
                             focusRequest: editor.linkOpenedBySelection ? 0 : editor.linkFocusRequest,
                             onSubmit: apply)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.12), in: .capsule)
            Button(editor.isExistingLink ? "Update" : "Insert", action: apply)
                .filledButtonStyle()
                .buttonBorderShape(.capsule)
                .disabled(!canApply)
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
    /// There's a camera, and Dabble Me may use it: not offered once it's been turned off for the
    /// app (Settings → Privacy → Camera, or "Don't Allow" when first asked), or by Screen Time.
    static var isAvailable: Bool {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return false }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status != .denied && status != .restricted
    }

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

/// The three formats, drawn as the letters every editor uses, in a serif like the writing's.
/// (The entry composer's bar and the template editor's.)
enum FormatLetter {
    case bold, italic, underline

    var label: Text {
        switch self {
        case .bold: Text("B").font(.system(size: 20, weight: .bold, design: .serif))
        case .italic: Text("I").font(.system(size: 20, weight: .medium, design: .serif)).italic()
        case .underline: Text("U").font(.system(size: 19, weight: .medium, design: .serif)).underline()
        }
    }
}

/// A format button for an editor's bar: lit, like a row's button while its row is open, while
/// the format's on.
struct FormatButton: View {
    let name: String
    let letter: FormatLetter
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            letter.label
                .frame(width: 40, height: 36)
                .background(isOn ? Color.accentColor.opacity(0.22) : .clear, in: .capsule)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
