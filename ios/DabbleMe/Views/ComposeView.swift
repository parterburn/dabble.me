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
    /// An unsaved draft from an earlier session was put back in the editor.
    @State private var restoredDraft: DraftStore.Draft?
    @State private var draftSave: Task<Void, Never>?
    @State private var suggestedTags: [String] = []
    @State private var isSuggestingTags = false
    @State private var suggestionError: String?
    @State private var pickingPhotos = false
    @State private var removesExistingPhoto = false
    @Environment(\.scenePhase) private var scenePhase
    private let draftKey: String
    private let originalBlocks: [DocumentBlock]

    init(mode: Mode, onSaved: @escaping (EntryDetail) -> Void = { _ in }) {
        self.mode = mode
        self.onSaved = onSaved
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
        if let date = draft?.date.flatMap(JournalDay.init) { _date = State(initialValue: date.localDate) }
        _editor = State(initialValue: RichTextEditorModel(blocks: draft?.blocks ?? original))
    }

    private var isNew: Bool {
        if case .new = mode { true } else { false }
    }

    /// In the order the user picked them.
    private var photos: [PreparedPhoto] { photoItems.compactMap { prepared[$0] } }
    private var hasChanges: Bool { editor.isDirty || !photoItems.isEmpty || restoredDraft != nil || removesExistingPhoto }
    private var canSave: Bool {
        guard !isSaving, !isLoadingPhotos else { return false }
        return isNew ? (!editor.isEmpty || !photos.isEmpty)
            : (!editor.isEmpty && (editor.isDirty || restoredDraft != nil || !photos.isEmpty || removesExistingPhoto))
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
                Divider()
                RichTextEditor(model: editor, insertItems: insertItems)
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
                // Only once used (from the bar's "+"), so the writing area stays as large as it can.
                if isSuggestingTags || !suggestedTags.isEmpty {
                    Divider()
                    hashtagSuggestions
                }
                if !photoItems.isEmpty || existingPhotoURL != nil {
                    Divider()
                    photoBar
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
                        if hasChanges { confirmingDiscard = true } else { DraftStore.clear(draftKey); dismiss() }
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
            .confirmationDialog(isNew ? "Discard this entry?" : "Discard your changes?",
                                isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    DraftStore.clear(draftKey)
                    dismiss()
                }
                Button("Keep Writing", role: .cancel) {}
            }
            .alert("Couldn't save", isPresented: .present($error)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .richTextLinkAlert(editor)
            .photosPicker(isPresented: $pickingPhotos, selection: $photoItems, maxSelectionCount: photoLimit,
                          selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
            .alert("No hashtag suggestions", isPresented: .present($suggestionError)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(suggestionError ?? "")
            }
            .onChange(of: photoItems) { Task { await preparePhotos() } }
            #if DEBUG
            .task { await attachDebugPhotos() }
            #endif
            .onChange(of: editor.revision) { scheduleDraftSave() }
            .onChange(of: date) { scheduleDraftSave() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { saveDraftNow() }
            }
            .onAppear {
                // Today's date in the journal's time zone, preferring the freshest source.
                if isNew, restoredDraft?.date == nil, let today = model.today?.day ?? model.me.flatMap({ JournalDay($0.today) }) {
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

    @ViewBuilder
    private var dateTitle: some View {
        if isNew {
            DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                .labelsHidden()
                .accessibilityLabel("Entry date")
        } else if case .edit(let entry) = mode {
            Text(entry.day?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()) ?? entry.date)
                .font(.headline)
        }
    }

    /// The editor bar's "+" menu.
    private var insertItems: [EditorInsertItem] {
        var items: [EditorInsertItem] = []
        if model.me?.canAddPhotos == true {
            let hasPhotos = !photoItems.isEmpty || existingPhotoURL != nil
            items.append(EditorInsertItem(title: hasPhotos ? "Add More Photos" : "Add Photos", systemImage: "photo.on.rectangle",
                                          isEnabled: photoItems.count < photoLimit) { pickingPhotos = true })
        } else if isNew {
            items.append(EditorInsertItem(title: "Add Photos", systemImage: "photo.on.rectangle",
                                          subtitle: "Part of Dabble Me PRO", isEnabled: false) {})
        }
        if JournalIntelligence.isEnabled(for: model.me) {
            items.append(EditorInsertItem(title: "Suggest Hashtags", systemImage: "number",
                                          subtitle: editor.characterCount < 20 ? "Write a little more first" : nil,
                                          isEnabled: editor.characterCount >= 20 && !isSuggestingTags) {
                Task { await suggestHashtags() }
            })
        }
        return items
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

    /// PRO, on-device (Apple Intelligence): hashtags for what's written so far. Tap one to add it.
    private var hashtagSuggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    suggestedTags = []
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Hide Suggestions")
                .disabled(isSuggestingTags)
                if isSuggestingTags {
                    ProgressView().controlSize(.small)
                    Text("Suggesting hashtags…").foregroundStyle(.secondary)
                } else {
                    Button("More", systemImage: "sparkles") { Task { await suggestHashtags() } }
                }
                ForEach(suggestedTags, id: \.self) { tag in
                    Button("#\(tag)") {
                        editor.appendHashtag(tag)
                        suggestedTags.removeAll { $0 == tag }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityHint("Adds this hashtag to the entry")
                }
            }
            .font(.subheadline)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func suggestHashtags() async {
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
    private var photoBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                if let existingPhotoURL {
                    existingThumbnail(existingPhotoURL)
                }
                ForEach(photoItems, id: \.self) { item in
                    thumbnail(for: item)
                }
                if photoItems.count < photoLimit {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: photoLimit,
                                 selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current) {
                        Label("Add More", systemImage: "photo.on.rectangle")
                            .frame(minHeight: 56)
                    }
                }
                let count = photoItems.count + (existingPhotoURL == nil ? 0 : 1)
                Text("\(count) of \(AppModel.maxPhotos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("\(count) of \(AppModel.maxPhotos) photos")
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 8)
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

    /// Prepares newly picked photos (downscale, strip location) and forgets removed ones.
    private func preparePhotos() async {
        let current = Set(photoItems)
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

    private func saveDraftNow() {
        guard !isSaving, editor.isDirty || restoredDraft != nil else { return }
        let blocks = editor.blocks
        if blocks.isEmpty {
            DraftStore.clear(draftKey)
        } else {
            DraftStore.save(.init(blocks: blocks, date: isNew ? JournalDay(localDate: date).iso : nil, savedAt: Date()), key: draftKey)
        }
    }

    private func save() async {
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
                onSaved(try await model.updateEntry(id: entry.id, document: editor.blocks, photos: photos,
                                                    removeImage: removesExistingPhoto) { uploadedCount = $0 })
            }
            draftSave?.cancel()
            DraftStore.clear(draftKey)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
