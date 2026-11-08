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
    @State private var isLoadingPhotos = false
    @State private var isSaving = false
    @State private var uploadedCount: Int?
    @State private var error: String?
    @State private var confirmingDiscard = false

    init(mode: Mode, onSaved: @escaping (EntryDetail) -> Void = { _ in }) {
        self.mode = mode
        self.onSaved = onSaved
        let blocks = if case .edit(let entry) = mode { entry.document ?? [] } else { [DocumentBlock]() }
        _editor = State(initialValue: RichTextEditorModel(blocks: blocks))
    }

    private var isNew: Bool {
        if case .new = mode { true } else { false }
    }

    /// In the order the user picked them.
    private var photos: [PreparedPhoto] { photoItems.compactMap { prepared[$0] } }
    private var hasChanges: Bool { editor.isDirty || !photoItems.isEmpty }
    private var canSave: Bool {
        guard !isSaving, !isLoadingPhotos else { return false }
        return isNew ? (!editor.isEmpty || !photos.isEmpty) : (!editor.isEmpty && editor.isDirty)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
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
                    photoBar
                }
            }
            .navigationTitle(isNew ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        HStack(spacing: 6) {
                            ProgressView()
                            if let uploadedCount, photos.count > 0 {
                                Text("\(uploadedCount) of \(photos.count)")
                                    .font(.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(uploadedCount.map { "Uploading photo \($0) of \(photos.count)" } ?? "Saving")
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(hasChanges || isSaving)
            .confirmationDialog(isNew ? "Discard this entry?" : "Discard your changes?",
                                isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Writing", role: .cancel) {}
            }
            .alert("Couldn't save", isPresented: .present($error)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .richTextLinkAlert(editor)
            .onChange(of: photoItems) { Task { await preparePhotos() } }
            .onAppear {
                if isNew, let today = model.me.flatMap({ JournalDay($0.today) }) {
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

            Text(photoFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(.vertical, 10)
    }

    private var photoFooter: String {
        if photoItems.isEmpty {
            return "Up to \(AppModel.maxPhotos) photos. Already wrote today? This adds to that entry."
        }
        let collage = photoItems.count > 1 ? " They'll be combined into a collage." : ""
        return "\(photoItems.count) of \(AppModel.maxPhotos) photos.\(collage) Location data is removed."
    }

    @ViewBuilder
    private func thumbnail(for item: PhotosPickerItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let photo = prepared[item], let image = UIImage(data: photo.data) {
                    Image(uiImage: image).resizable().scaledToFill()
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

    /// Prepares newly picked photos (downscale, strip location) and forgets removed ones.
    private func preparePhotos() async {
        let current = Set(photoItems)
        prepared = prepared.filter { current.contains($0.key) }
        let pending = photoItems.filter { prepared[$0] == nil }
        guard !pending.isEmpty else { return }

        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        var failed = 0
        for item in pending {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw PhotoError.unreadable }
                let photo = try await Task.detached(priority: .userInitiated) { try PhotoPreparer.prepare(data) }.value
                if photoItems.contains(item) { prepared[item] = photo }
            } catch {
                failed += 1
                photoItems.removeAll { $0 == item }
            }
        }
        if failed > 0 {
            error = failed == 1 ? "One photo couldn't be added." : "\(failed) photos couldn't be added."
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
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
