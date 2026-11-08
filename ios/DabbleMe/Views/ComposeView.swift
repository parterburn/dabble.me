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
    private var hasChanges: Bool { editor.isDirty || !photoItems.isEmpty || restoredDraft != nil }
    private var canSave: Bool {
        guard !isSaving, !isLoadingPhotos else { return false }
        return isNew ? (!editor.isEmpty || !photos.isEmpty) : (!editor.isEmpty && (editor.isDirty || restoredDraft != nil))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if restoredDraft != nil { draftBanner }
                Divider()
                RichTextEditor(model: editor)
                    .overlay(alignment: .topLeading) {
                        if editor.isEmpty {
                            Text("How was your day?")
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 16)
                                .padding(.leading, 17)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                if isNew {
                    Divider()
                    if model.me?.canAddPhotos == true {
                        photoBar
                    } else {
                        Label("Adding photos is part of Dabble Me PRO.", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                    }
                }
            }
            .overlay {
                if isSaving { savingOverlay }
            }
            .navigationTitle(isNew ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
    private var header: some View {
        Group {
            if isNew {
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            } else if case .edit(let entry) = mode {
                LabeledContent("Date", value: entry.day?.long ?? entry.date)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
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

    private var photoBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(photoItems, id: \.self) { item in
                        thumbnail(for: item)
                    }
                    if photoItems.count < AppModel.maxPhotos {
                        PhotosPicker(selection: $photoItems, maxSelectionCount: AppModel.maxPhotos,
                                     selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current) {
                            Label(photoItems.isEmpty ? "Add Photos" : "Add More", systemImage: "photo.on.rectangle")
                                .frame(minHeight: 56)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)

            if let photoFooter {
                Text(photoFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 10)
    }

    /// Only once photos are picked, to keep the composer compact.
    private var photoFooter: String? {
        guard !photoItems.isEmpty else { return nil }
        let collage = photoItems.count > 1 ? " They'll be combined into a collage." : ""
        return "\(photoItems.count) of \(AppModel.maxPhotos) photos.\(collage) Location data is removed."
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
            }
            .offset(x: 6, y: -6)
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
        guard isNew, photoItems.isEmpty,
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
                onSaved(try await model.updateEntry(id: entry.id, document: editor.blocks))
            }
            draftSave?.cancel()
            DraftStore.clear(draftKey)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
