import SwiftUI

/// A timeline/search/On This Day row: first tap expands the whole entry inline (like a long post
/// in a feed), a second tap opens it. Swipe right to reflect (PRO, Apple Intelligence); swipe left
/// to Open, or for Actions (Reflect, Edit, Delete and the entry's tags).
struct TimelineEntryRow: View {
    let entry: EntrySummary
    var showsYear = false
    let isExpanded: Bool
    /// The expanded entry's date, unless a sticky header above already shows it.
    var showsDateWhenExpanded = true
    let actions: EntryActions
    let onTap: () -> Void
    let onOpen: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var full: EntryDetail?
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17

    var body: some View {
        Group {
            if isExpanded {
                expanded
            } else {
                EntryRow(entry: entry, showsYear: showsYear)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
        // Reload the full entry whenever its summary changes (an edit, or a refresh that brought
        // new text from the web or email), not just the first time it's expanded.
        .task(id: "\(isExpanded)|\(entry.updatedAt)") {
            guard isExpanded else { return }
            if full?.updatedAt != entry.updatedAt { full = try? await model.entry(id: entry.id) }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if JournalIntelligence.isEnabled(for: model.me) {
                Button {
                    Task { await actions.reflect(on: entry.id, model: model) }
                } label: {
                    Label("Reflect", icon: "slab-thought-bubble")
                }
                .tint(.accentColor)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // The first is the full swipe.
            Button(action: onOpen) {
                Label("Open", icon: "slab-expand")
            }
            .tint(.accentColor)
            Button {
                Task { await actions.showActions(for: entry.id, model: model) }
            } label: {
                Label("Actions", icon: "slab-bolt")
            }
            .tint(.gray)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Opens the entry" : "Shows the whole entry")
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsDateWhenExpanded {
                Text(entry.day?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()) ?? entry.date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let document = full?.document {
                DocumentText(blocks: document, font: .system(size: bodySize, design: .serif), scale: 1, bodySize: bodySize)
            } else {
                Text(RichText.linkingHashtags(in: AttributedString.journal(full?.bodyText ?? entry.previewText ?? entry.excerpt)))
                    .font(.system(size: bodySize, design: .serif))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if entry.imageProcessing || entry.imageURL != nil {
                EntryPhoto(url: entry.thumbnailURL(width: 1000), isProcessing: entry.imageProcessing)
                    .frame(maxHeight: 320)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .padding(.vertical, 6)
    }
}

/// Reflect/Edit from a row's swipe actions: loads the entry, then shows the reflection or the editor.
@MainActor
@Observable
final class EntryActions {
    var editing: EntryDetail?
    var reflection: EntryReflection?
    /// The Actions sheet (swipe left → Actions), and an entry waiting on "Delete?".
    var sheet: EntryDetail?
    var deleting: EntryDetail?
    var isWorking = false
    var error: String?

    func showActions(for id: Int, model: AppModel) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            sheet = try await model.entry(id: id)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ entry: EntryDetail, model: AppModel) async {
        do {
            try await model.deleteEntry(id: entry.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reflect(on id: Int, model: AppModel) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            reflection = try await model.reflection(on: try await model.entry(id: id))
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension View {
    func entryActionSheets(_ actions: EntryActions) -> some View {
        modifier(EntryActionSheets(actions: actions))
    }
}

private struct EntryActionSheets: ViewModifier {
    @Bindable var actions: EntryActions
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.editing) { entry in
                ComposeView(mode: .edit(entry))
            }
            .sheet(item: $actions.reflection) { reflection in
                ReflectionSheet(reflection: reflection)
            }
            .sheet(item: $actions.sheet) { entry in
                EntryActionsSheet(entry: entry, canReflect: JournalIntelligence.isEnabled(for: model.me) && !entry.bodyText.isEmpty,
                                  canEdit: model.me?.canEdit == true) { action in
                    actions.sheet = nil
                    switch action {
                    case .reflect: Task { await actions.reflect(on: entry.id, model: model) }
                    case .edit: if entry.document != nil { actions.editing = entry } else { openURL(entry.webUrl) }
                    case .delete: actions.deleting = entry
                    case .web: openURL(entry.webUrl)
                    case .search(let tag): if let url = URL(string: "\(RichText.hashtagScheme):\(tag)") { openURL(url) }
                    }
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: Binding(get: { actions.deleting != nil }, set: { if !$0 { actions.deleting = nil } }),
                                titleVisibility: .visible, presenting: actions.deleting) { entry in
                Button("Delete Entry", role: .destructive) { Task { await actions.delete(entry, model: model) } }
            } message: { _ in
                Text("This can't be undone.")
            }
            .overlay {
                if actions.isWorking {
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
            }
            .alert("Something went wrong", isPresented: .present($actions.error)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actions.error ?? "")
            }
    }
}
