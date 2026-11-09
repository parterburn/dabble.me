import SwiftUI

/// Settings → Manage Hashtags (PRO): a date for a #tag (a birthday, an anniversary), so entries
/// show how long it had been ("3 years and 4 months"), like the web settings' dated tags. Change a
/// date in place, swipe (or Edit) to remove, or add one from the tags you use or by name.
struct TagDatesView: View {
    @Environment(AppModel.self) private var model
    @State private var list: TagDateList?
    @State private var loadError: String?
    @State private var error: String?
    @State private var adding: String?

    var body: some View {
        Group {
            if let list {
                Form {
                    Section {
                        if list.hashtags.isEmpty {
                            Text("No dated hashtags yet.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(list.hashtags) { item in
                            DatePicker(selection: Binding(get: { item.day?.localDate ?? .now }, set: { date in
                                Task { await change(item, to: date) }
                            }), displayedComponents: .date) {
                                Text("#\(item.tag)")
                            }
                        }
                        .onDelete { offsets in
                            let items = offsets.map { list.hashtags[$0] }
                            Task { for item in items { await remove(item) } }
                        }
                    } footer: {
                        Text("Entries with a dated hashtag show how long it had been, like a child's age or years since an anniversary.")
                    }

                    Section {
                        ForEach(list.suggestions, id: \.self) { tag in
                            Button { adding = tag } label: {
                                Label("#\(tag)", icon: "slab-plus")
                            }
                        }
                        Button { adding = "" } label: {
                            Label("Another Hashtag…", icon: "slab-plus")
                        }
                    } header: {
                        Text("Add a Date")
                    } footer: {
                        if !list.suggestions.isEmpty {
                            Text("Hashtags you've used lately.")
                        }
                    }
                }
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn't load your hashtags", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .toolbar {
            if list?.hashtags.isEmpty == false { EditButton() }
        }
        .navigationTitle("Manage Hashtags")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { adding.map(NewTag.init) }, set: { adding = $0?.tag })) { new in
            AddTagDateSheet(tag: new.tag) { tag, date in
                await add(tag: tag, date: date)
            }
        }
        .alert("Couldn't save", isPresented: .present($error)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .task { if list == nil { await load() } }
    }

    private struct NewTag: Identifiable {
        let tag: String
        var id: String { tag }
    }

    private func load() async {
        do {
            list = try await model.tagDates()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func change(_ item: TagDate, to date: Date) async {
        let iso = JournalDay(localDate: date).iso
        guard iso != item.date else { return }
        do {
            _ = try await model.updateTagDate(id: item.id, date: iso)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ item: TagDate) async {
        do {
            try await model.removeTagDate(id: item.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Returns the problem, if any (the sheet stays open to fix it).
    private func add(tag: String, date: Date) async -> String? {
        do {
            _ = try await model.addTagDate(tag: tag, date: JournalDay(localDate: date).iso)
            await load()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

/// Name (unless picked from your tags) and date for a new dated hashtag.
private struct AddTagDateSheet: View {
    let tag: String
    let onSave: (String, Date) async -> String?
    @State private var name = ""
    @State private var error: String?
    @State private var date = Date.now
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    private var cleaned: String {
        name.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }

    var body: some View {
        NavigationStack {
            Form {
                if tag.isEmpty {
                    HStack(spacing: 2) {
                        Text("#").foregroundStyle(.secondary)
                        TextField("Hashtag", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(tag.isEmpty ? "New Dated Hashtag" : "#\(tag)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        isSaving = true
                        Task {
                            error = await onSave(tag.isEmpty ? cleaned : tag, date)
                            isSaving = false
                            if error == nil { dismiss() }
                        }
                    }
                    .disabled(isSaving || (tag.isEmpty && cleaned.isEmpty))
                }
            }
        }
        .presentationDetents([.medium])
    }
}
