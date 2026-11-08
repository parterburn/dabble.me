import SwiftUI

/// A timeline/search row: first tap expands the whole entry inline (like a long post in a feed),
/// a second tap opens it. Swipe right to reflect (PRO, Apple Intelligence), left to edit (PRO).
struct TimelineEntryRow: View {
    let entry: EntrySummary
    var showsYear = false
    let isExpanded: Bool
    let actions: EntryActions
    let onTap: () -> Void

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
        .task(id: isExpanded) {
            if isExpanded, full == nil { full = try? await model.entry(id: entry.id) }
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
            if model.me?.canEdit == true {
                Button {
                    Task { await actions.edit(entry.id, model: model, openURL: openURL) }
                } label: {
                    Label("Edit", icon: "slab-edit")
                }
                .tint(.gray)
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Opens the entry" : "Shows the whole entry")
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(entry.day?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()) ?? entry.date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 3) {
                    Text("Open")
                    appIcon("slab-expand")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            }
            if let document = full?.document {
                DocumentText(blocks: document, font: .system(size: bodySize, design: .serif), scale: 1, bodySize: bodySize)
            } else {
                Text(full.map { RichText.linkingHashtags(in: AttributedString.journal($0.bodyText)) } ?? AttributedString(entry.excerpt))
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
    var isWorking = false
    var error: String?

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

    func edit(_ id: Int, model: AppModel, openURL: OpenURLAction) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let entry = try await model.entry(id: id)
            // Formatting only the web editor keeps: edit there so nothing is lost.
            if entry.document == nil { openURL(entry.webUrl) } else { editing = entry }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension View {
    func entryActionSheets(_ actions: EntryActions) -> some View {
        @Bindable var actions = actions
        return sheet(item: $actions.editing) { entry in
            ComposeView(mode: .edit(entry))
        }
        .sheet(item: $actions.reflection) { reflection in
            ReflectionSheet(reflection: reflection)
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
