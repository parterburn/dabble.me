import SwiftUI

/// An entry's actions in a sheet from the bottom (swipe left → Actions in a list, or swipe left on
/// the entry itself): Reflect, Edit, Delete, and its #tags. Dated tags show how long it had been on
/// that day ("3 years and 4 months since entry") without opening the entry.
struct EntryActionsSheet: View {
    enum Action { case reflect, edit, delete, web, search(String) }

    let entry: EntryDetail
    let canReflect: Bool
    let canEdit: Bool
    /// Free accounts can delete but not edit.
    let canDelete: Bool
    let perform: (Action) -> Void

    private var tags: [(tag: String, age: String?)] {
        let dated = Dictionary((entry.datedHashtags ?? []).map { ($0.tag.lowercased(), $0.age) }, uniquingKeysWith: { first, _ in first })
        return entry.hashtags.map { ($0, dated[$0.lowercased()]) }
    }

    private var height: CGFloat {
        let actions = (canReflect ? 1 : 0) + (canEdit ? 1 : 0) + (canDelete ? 1 : 0)
        let tagRows = tags.reduce(0) { $0 + ($1.age == nil ? 1 : 1.6) }
        return min(70 + CGFloat(actions) * 56 + (tags.isEmpty ? 0 : 40 + tagRows * 40), 640)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.day?.long ?? entry.date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                if canReflect {
                    row("Reflect on This Entry", "slab-sparkles", .reflect)
                }
                if canEdit {
                    row(entry.document != nil ? "Edit" : "Edit on dabble.me", "slab-edit", .edit)
                }
                if canDelete {
                    row("Delete", "slab-trash", .delete, role: .destructive)
                }
                if !tags.isEmpty {
                    Label("Tags", icon: "slab-tag")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                    ForEach(tags, id: \.tag) { item in
                        Button {
                            perform(.search(item.tag))
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("#\(item.tag)")
                                        .foregroundStyle(.tint)
                                    if let age = item.age {
                                        Text(age.prefix(1).uppercased() + age.dropFirst())
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ActionsSheetTag")
                        .accessibilityLabel("#\(item.tag)")
                        .accessibilityValue(item.age ?? "")
                        .accessibilityHint("Searches for this hashtag")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height), .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ title: String, _ symbol: String, _ action: Action, role: ButtonRole? = nil) -> some View {
        Button(role: role) {
            perform(action)
        } label: {
            Label(title, icon: symbol)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(role == .destructive ? .red : nil)
    }
}
