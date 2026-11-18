import SwiftUI

/// An entry's actions in a sheet from the bottom (swipe left → Actions in a list, or swipe left on
/// the entry itself), under its date and how long ago that was: Open (from a list: the entry in full), Reflect, Edit, Share, Delete, and its #tags. Dated tags show how long it had been on
/// that day ("3 years and 4 months since entry") without opening the entry. Delete confirms right
/// in its button: tap, then hold it until it fills.
struct EntryActionsSheet: View {
    enum Action { case open, reflect, edit, delete, web, search(String) }

    let entry: EntryDetail
    /// From a list: the entry can be opened in full. (Not from the entry's own page.)
    var canOpen = false
    let canReflect: Bool
    let canEdit: Bool
    /// Free accounts can delete but not edit.
    let canDelete: Bool
    let perform: (Action) -> Void

    private var tags: [(tag: String, age: String?)] {
        let dated = Dictionary((entry.datedHashtags ?? []).map { ($0.tag.lowercased(), $0.age) }, uniquingKeysWith: { first, _ in first })
        return entry.hashtags.map { ($0, dated[$0.lowercased()]) }
    }

    @State private var isPreparingShare = false
    /// For the journal's own today (optional: nothing here depends on it being there).
    @Environment(AppModel.self) private var model: AppModel?

    /// How long ago the entry's day was, as of today ("3 years, 2 months ago").
    private var ago: String? {
        entry.day.map { $0.ago(from: model?.today?.day ?? JournalDay(localDate: .now)) }
    }

    /// The entry's photo, once it's there to share.
    private var photoURL: URL? { entry.imageProcessing ? nil : entry.imageURL }
    private var canShare: Bool { sharedText != nil || photoURL != nil }

    /// Opens the share sheet with the entry's words and, after them, its photo (as a file, so
    /// the sheet shows it and gives it a name). A photo that can't be fetched is left out.
    private func share() async {
        isPreparingShare = true
        defer { isPreparingShare = false }
        var items: [Any] = []
        var shownPhoto: UIImage?
        if let sharedText { items.append(sharedText) }
        if let photoURL {
            let photo = RemotePhoto(url: photoURL, day: entry.day)
            await photo.load()
            if let image = photo.image {
                shownPhoto = image
                let file = FileManager.default.temporaryDirectory.appending(path: "Dabble Me – \(entry.date).jpg")
                if let data = image.jpegData(compressionQuality: 0.9), (try? data.write(to: file, options: .atomic)) != nil {
                    items.append(file)
                } else {
                    items.append(image)
                }
            }
        }
        // Under the sheet: the entry on a page of its own (see `presentShareSheet`).
        PhotoActions.presentShareSheet(items, over: AnyView(SharedEntryPage(date: entry.day?.long ?? entry.date, words: sharedWords, photo: shownPhoto)))
    }

    /// The entry's words as they read, without its date.
    private var sharedWords: String {
        (entry.document.map { RichText.segments(for: $0).map(\.text).joined() }
            ?? String(AttributedString.journal(entry.bodyText).characters)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The words Share hands over: the entry's date, then what's written. Nil for an entry
    /// with none (a photo alone).
    private var sharedText: String? {
        // As it reads, not as it's stored: the document's own text (list items with their
        // bullets), or, without one, the entry's text with its Markdown marks taken out.
        let body = entry.document.map { RichText.segments(for: $0).map(\.text).joined() }
            ?? String(AttributedString.journal(entry.bodyText).characters)
        return Self.sharedText(date: entry.day?.long ?? entry.date, body: body)
    }

    static func sharedText(date: String, body: String) -> String? {
        let words = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? nil : date + "\n\n" + words
    }

    private var height: CGFloat {
        let actions = (canOpen ? 1 : 0) + (canReflect ? 1 : 0) + (canEdit ? 1 : 0) + (canDelete ? 1 : 0) + (canShare ? 1 : 0)
        // Pills wrap, a few to a row; a dated one, with its age beside it, mostly has a row to itself.
        let dated = tags.count(where: { $0.age != nil })
        let pillRows = CGFloat(dated + (tags.count - dated + 2) / 3) * 44
        // (And a line for how long ago, under the date.)
        return min(70 + (ago == nil ? 0 : 20) + CGFloat(actions) * 62 + (tags.isEmpty ? 0 : 50 + pillRows), 640)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // The date in full, and under it, as its subtitle in a quieter color, how long ago
                // that was. Always a line each.
                VStack(alignment: .leading, spacing: 2) {
                    dateLine
                    agoLine
                }
                .padding(.bottom, 4)
                if canOpen {
                    row("Open", "slab-expand", .open)
                }
                if canReflect {
                    row("Reflection", "slab-sparkles", .reflect)
                }
                if canEdit {
                    row(entry.document != nil ? "Edit" : "Edit on dabble.me", "slab-edit", .edit)
                }
                // The entry's words, and its photo when it has one, to iOS's share sheet, for
                // whatever's there to take them: read aloud (Accessibility Reader), copied,
                // printed, sent. Only when asked for.
                if canShare {
                    Button {
                        Task { await share() }
                    } label: {
                        HStack {
                            Label("Share", icon: "slab-arrow-up-from-line")
                            Spacer()
                            // (Fetching the photo, the first time it's not to hand.)
                            if isPreparingShare { TypingDots(size: .small) }
                        }
                    }
                    .buttonStyle(ActionRowStyle())
                    .disabled(isPreparingShare)
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

    private var dateLine: some View {
        Text(entry.day?.long ?? entry.date)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    @ViewBuilder
    private var agoLine: some View {
        if let ago {
            Text(ago)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("ActionsSheetAgo")
        }
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
                        Color.deleteRed.frame(width: geometry.size.width * fill)
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

/// What Share is sharing, as a plain page under the share sheet: the entry's date, its words and
/// its photo, and nothing to tap. For a destination that reads the screen rather than what it's
/// handed, this is the screen.
private struct SharedEntryPage: View {
    let date: String
    let words: String
    let photo: UIImage?
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(date)
                    .font(.headline)
                if !words.isEmpty {
                    Text(words)
                        .font(.system(.body, design: fontStyle.design))
                        .lineSpacing(5)
                }
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .background(Color(.systemBackground))
    }
}
