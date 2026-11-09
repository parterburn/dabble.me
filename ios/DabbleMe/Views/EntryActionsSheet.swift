import SwiftUI

/// An entry's actions in a sheet from the bottom (swipe left → Actions in a list, or swipe left on
/// the entry itself): Reflect, Edit, Delete, and its #tags. Dated tags show how long it had been on
/// that day ("3 years and 4 months since entry") without opening the entry. Delete confirms right
/// in its button: tap, then hold it until it fills.
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
                    HoldToDeleteButton { perform(.delete) }
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

    private func row(_ title: String, _ symbol: String, _ action: Action) -> some View {
        Button {
            perform(action)
        } label: {
            Label(title, icon: symbol)
        }
        .buttonStyle(ActionRowStyle())
    }
}

/// The Actions sheet's buttons: black text and icon, medium weight, on a light capsule.
private struct ActionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .actionRow(pressed: configuration.isPressed)
    }
}

private extension View {
    /// `fill` (0–1) fills the capsule red from the left, turning the text white once it's past half.
    func actionRow(pressed: Bool = false, fill: CGFloat = 0) -> some View {
        font(.body.weight(.medium))
            .foregroundStyle(fill > 0.5 ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 20)
            .background {
                ZStack(alignment: .leading) {
                    Color.primary.opacity(pressed ? 0.14 : 0.07)
                    GeometryReader { geometry in
                        Color.red.frame(width: geometry.size.width * fill)
                    }
                }
                .clipShape(.capsule)
            }
            .contentShape(.capsule)
    }
}

/// Delete without an alert: the first tap turns it into "Hold to Delete", and holding it for two
/// seconds fills it red and deletes. Letting go early empties it; left alone, it goes back to
/// "Delete". VoiceOver can't hold, so there a second activation deletes.
private struct HoldToDeleteButton: View {
    let delete: () -> Void
    @State private var armed = false
    @State private var progress: CGFloat = 0
    @State private var disarm: Task<Void, Never>?
    private let holdTime: Double = 2

    var body: some View {
        Label(armed ? "Hold to Delete" : "Delete", icon: "slab-trash")
            .contentTransition(.opacity)
            .actionRow(fill: progress)
            .onTapGesture {
                guard !armed else { return }
                withAnimation(.snappy(duration: 0.2)) { armed = true }
                scheduleDisarm()
            }
            .onLongPressGesture(minimumDuration: holdTime, maximumDistance: 30) {
                guard armed else { return }
                disarm?.cancel()
                delete()
            } onPressingChanged: { pressing in
                guard armed else { return }
                if pressing {
                    disarm?.cancel()
                    withAnimation(.linear(duration: holdTime)) { progress = 1 }
                } else if progress < 1 {
                    withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
                    scheduleDisarm()
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, isArmed in isArmed }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(armed ? "Hold to Delete" : "Delete")
            .accessibilityHint(armed ? "Deletes this entry" : "Asks you to confirm")
            .accessibilityAction {
                if armed { delete() } else { armed = true; scheduleDisarm() }
            }
    }

    private func scheduleDisarm() {
        disarm?.cancel()
        disarm = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2)) { armed = false }
        }
    }
}
