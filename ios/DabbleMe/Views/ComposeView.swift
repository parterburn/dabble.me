import PhotosUI
import SwiftUI

struct ComposeView: View {
    enum Mode {
        case new
        case edit(EntryDetail)
    }

    let mode: Mode
    var onSaved: (EntryDetail) -> Void = { _ in }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var date = Date()
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: PreparedPhoto?
    @State private var preview: Image?
    @State private var isLoadingPhoto = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmingDiscard = false
    @FocusState private var editorFocused: Bool
    private let originalText: String

    init(mode: Mode, onSaved: @escaping (EntryDetail) -> Void = { _ in }) {
        self.mode = mode
        self.onSaved = onSaved
        let initial = if case .edit(let entry) = mode { entry.editableText ?? "" } else { "" }
        originalText = initial
        _text = State(initialValue: initial)
    }

    private var isNew: Bool {
        if case .new = mode { true } else { false }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasChanges: Bool { text != originalText || photo != nil }
    private var canSave: Bool {
        guard !isSaving, !isLoadingPhoto else { return false }
        return isNew ? (!trimmed.isEmpty || photo != nil) : (!trimmed.isEmpty && hasChanges)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isNew {
                        DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    } else if case .edit(let entry) = mode {
                        LabeledContent("Date", value: entry.day?.long ?? entry.date)
                    }
                } footer: {
                    if isNew {
                        Text("Already wrote on this day? This will be added to that entry.")
                    }
                }

                Section {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .serif))
                        .frame(minHeight: 260)
                        .focused($editorFocused)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("How was your day?")
                                    .font(.system(.body, design: .serif))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityLabel("Entry")
                }

                if isNew {
                    photoSection
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
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(hasChanges || isSaving)
            .confirmationDialog("Discard this entry?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Writing", role: .cancel) {}
            }
            .alert("Couldn't save", isPresented: .present($error)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .onChange(of: photoItem) { Task { await loadPhoto() } }
            .onAppear {
                editorFocused = true
                if isNew, let today = model.me.flatMap({ JournalDay($0.today) }) {
                    date = today.localDate
                }
            }
        }
    }

    private var photoSection: some View {
        Section {
            if let preview {
                preview
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(.rect(cornerRadius: 10))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Selected photo")
                Button("Remove Photo", systemImage: "xmark.circle", role: .destructive) {
                    photoItem = nil
                }
            } else if isLoadingPhoto {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .current) {
                    Label("Add Photo", systemImage: "photo.on.rectangle")
                }
            }
        } footer: {
            Text("One photo per entry. Location data is removed before upload.")
        }
    }

    private func loadPhoto() async {
        guard let item = photoItem else {
            photo = nil
            preview = nil
            return
        }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw PhotoError.unreadable }
            let prepared = try await Task.detached(priority: .userInitiated) { try PhotoPreparer.prepare(data) }.value
            photo = prepared
            preview = UIImage(data: prepared.data).map(Image.init(uiImage:))
        } catch {
            self.error = "That photo couldn't be added. Try a different one."
            photoItem = nil
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            switch mode {
            case .new:
                let result = try await model.createEntry(day: JournalDay(localDate: date), text: trimmed, photo: photo)
                onSaved(result.entry)
            case .edit(let entry):
                onSaved(try await model.updateEntry(id: entry.id, text: trimmed))
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
