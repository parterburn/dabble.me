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
        // Pills wrap, a few to a row; dated ones are taller.
        let pillRows = CGFloat((tags.count + 2) / 3) * (tags.contains { $0.age != nil } ? 64 : 44)
        return min(70 + CGFloat(actions) * 62 + (tags.isEmpty ? 0 : 50 + pillRows), 640)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.day?.long ?? entry.date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                if canReflect {
                    row("Reflection", "slab-sparkles", .reflect)
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
                    // The same pills as under entries; dated ones show their age. Tap to search.
                    FlowLayout(spacing: 8) {
                        ForEach(tags, id: \.tag) { item in
                            Button {
                                perform(.search(item.tag))
                            } label: {
                                HashtagPill(tag: item.tag, age: item.age)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ActionsSheetTag")
                            .accessibilityLabel("#\(item.tag)")
                            .accessibilityValue(item.age ?? "")
                            .accessibilityHint("Searches for this hashtag")
                        }
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
    /// Set when a hold lasts the full time. Not `progress == 1`: animating the fill sets
    /// `progress` to 1 at once (only its drawing takes two seconds), so it can't tell an early
    /// release from a finished hold.
    @State private var completed = false
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
                completed = true
                disarm?.cancel()
                delete()
            } onPressingChanged: { pressing in
                guard armed, !completed else { return }
                if pressing {
                    disarm?.cancel()
                    withAnimation(.linear(duration: holdTime)) { progress = 1 }
                } else {
                    // Let go early: empty it, and go back to "Delete" if left alone.
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
