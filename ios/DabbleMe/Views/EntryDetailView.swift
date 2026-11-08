import SwiftUI

/// One entry. Pinch to change text size; pull down for a reflection (PRO, Apple Intelligence);
/// swipe left for its actions (reflect, edit, delete).
struct EntryDetailView: View {
    let entryID: Int

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var entry: EntryDetail?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var pinchStart: ReadingTextSize?
    @State private var textSizeHUD: String?
    @State private var reflection: EntryReflection?
    @State private var isReflecting = false
    @State private var showingActions = false
    /// Tapping the title switches between the date and how long ago it was (remembered).
    @AppStorage("entry.showsRelativeDate") private var showsRelativeDate = false
    @State private var hideHUD: Task<Void, Never>?
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard

    private var id: Int { entryID }

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    EntryBody(entry: entry)
                        .padding()
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                        .simultaneousGesture(pinchToResize)
                }
                .simultaneousGesture(swipeForActions)
                .modifier(PullToReflect(action: canReflect(entry) ? { await reflect(on: entry, showsProgress: false) } : nil))
                .overlay {
                    if let textSizeHUD {
                        Text(textSizeHUD)
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: .capsule)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: textSizeHUD)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn't load this entry", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(entry?.day?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let entry {
                ToolbarItem(placement: .principal) { dateTitle(for: entry) }
                ToolbarItem(placement: .primaryAction) { menu(for: entry) }
            }
        }
        .sheet(isPresented: $showingActions) {
            if let entry {
                EntryActionsSheet(entry: entry, canReflect: JournalIntelligence.isEnabled(for: model.me) && !entry.bodyText.isEmpty,
                                  canEdit: model.me?.canEdit == true) { action in
                    showingActions = false
                    switch action {
                    case .reflect: Task { await reflect(on: entry) }
                    case .edit: if entry.document != nil { editing = true } else { openURL(entry.webUrl) }
                    case .delete: confirmingDelete = true
                    case .web: openURL(entry.webUrl)
                    }
                }
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Entry", role: .destructive) { Task { await delete() } }
        } message: {
            Text("This can't be undone.")
        }
        .sheet(isPresented: $editing) {
            if let entry {
                ComposeView(mode: .edit(entry)) { self.entry = $0 }
            }
        }
        .sheet(item: $reflection) { reflection in
            ReflectionSheet(reflection: reflection)
        }
        .overlay {
            if isReflecting {
                ProgressView("Reflecting…")
                    .padding(20)
                    .background(.regularMaterial, in: .rect(cornerRadius: 14))
            }
        }
        .alert("Something went wrong", isPresented: .present($actionError)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: showingActions) { _, showing in showing }
        .sensoryFeedback(.selection, trigger: textSize)
        .disabled(isDeleting)
        .task { await load() }
        .task(id: entry?.imageProcessing) {
            // Swap the placeholder for the finished photo/collage as soon as it's ready.
            while entry?.imageProcessing == true, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await load()
            }
        }
    }

    private func menu(for entry: EntryDetail) -> some View {
        Menu {
            actionButtons(for: entry)
        } label: {
            Label("Entry Actions", icon: "slab-edit")
        }
    }

    /// Swipe left anywhere on the entry for its actions (a right swipe is iOS's "go back").
    private var swipeForActions: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                if dx < -80, abs(dy) < abs(dx) * 0.5 { showingActions = true }
            }
    }

    @ViewBuilder
    private func actionButtons(for entry: EntryDetail) -> some View {
            // Reflect is pull-down (and the swipe-left sheet), not in this menu.
            if model.me?.canEdit == true {
                if entry.document != nil {
                    Button { editing = true } label: { Label("Edit", icon: "slab-edit") }
                } else {
                    // Formatting the app can't represent (styles, quotes, AI replies) stays web-only so nothing gets lost.
                    Button("Edit on dabble.me", systemImage: "safari") { openURL(entry.webUrl) }
                }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", icon: "slab-trash") }
            } else {
                Button("Open on dabble.me", systemImage: "safari") { openURL(entry.webUrl) }
            }
    }

    /// Tap: the date or how long ago it was.
    private func dateTitle(for entry: EntryDetail) -> some View {
        let full = entry.day?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()) ?? entry.date
        let today = model.today?.day ?? JournalDay(localDate: .now)
        let relative = entry.day.map { $0.relative(to: today) } ?? full
        return Text(showsRelativeDate ? relative : full)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .contentTransition(.opacity)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(.rect)
            .onTapGesture { showsRelativeDate.toggle() }
            .accessibilityElement()
            .accessibilityLabel(entry.day?.long ?? entry.date)
            .accessibilityValue(relative)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Switches between the date and how long ago it was")
            .accessibilityAction { showsRelativeDate.toggle() }
            .animation(.easeOut(duration: 0.15), value: showsRelativeDate)
    }

    private func canReflect(_ entry: EntryDetail) -> Bool {
        JournalIntelligence.isEnabled(for: model.me) && !entry.bodyText.isEmpty
    }

    /// `showsProgress`: false when pulled down, where the refresh spinner already shows it's working.
    private func reflect(on entry: EntryDetail, showsProgress: Bool = true) async {
        isReflecting = showsProgress
        defer { isReflecting = false }
        do {
            reflection = try await model.reflection(on: entry)
        } catch is CancellationError {
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Pinch to resize text

    /// Each ~25% of pinch moves one text size step (Small … Largest).
    private var pinchToResize: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.04)
            .onChanged { value in
                let start = pinchStart ?? textSize
                if pinchStart == nil { pinchStart = start }
                let steps = Int((log(value.magnification) / log(1.25)).rounded(.towardZero))
                let index = min(max(start.rawValue + steps, 0), ReadingTextSize.allCases.count - 1)
                if let size = ReadingTextSize(rawValue: index), size != textSize { textSize = size }
                showHUD()
            }
            .onEnded { _ in
                pinchStart = nil
                hideHUD?.cancel()
                hideHUD = Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    guard !Task.isCancelled else { return }
                    textSizeHUD = nil
                }
            }
    }

    private func showHUD() {
        hideHUD?.cancel()
        textSizeHUD = "Text Size: \(textSize.label)"
    }

    // MARK: - Loading

    private func load() async {
        do {
            entry = try await model.entry(id: id)
            loadError = nil
        } catch is CancellationError {
        } catch {
            if entry == nil { loadError = error.localizedDescription } else { actionError = error.localizedDescription }
        }
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await model.deleteEntry(id: id)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct EntryBody: View {
    let entry: EntryDetail
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17

    private var bodyFont: Font { .system(size: bodySize * textSize.scale, design: .serif) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let document = entry.document {
                DocumentText(blocks: document, font: bodyFont, scale: textSize.scale, bodySize: bodySize)
            } else if !entry.bodyText.isEmpty {
                Text(RichText.linkingHashtags(in: AttributedString.journal(entry.bodyText)))
                    .font(bodyFont)
                    .lineSpacing(5 * textSize.scale)
                    .textSelection(.enabled)
            }

            if let dated = entry.datedHashtags, !dated.isEmpty {
                DatedHashtagRow(hashtags: dated)
            }

            if !entry.songs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Songs")
                        .font(.headline)
                    ForEach(entry.songs, id: \.self) { song in
                        Link(destination: song.spotifyUrl) {
                            Label(song.label, icon: "slab-music")
                        }
                    }
                }
            }

            // Text first: Dabble Me is about the writing; photos follow it.
            if entry.imageProcessing || entry.imageURL != nil {
                EntryPhoto(url: entry.imageURL, isProcessing: entry.imageProcessing)
            }
        }
    }
}

extension AttributedString {
    /// Entry text comes from the server as light Markdown (bold, italics, links); render it,
    /// falling back to plain text if it doesn't parse.
    static func journal(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// An entry's blocks as text. Paragraphs are separated by a blank line's worth of space, and
/// list items hang: wrapped lines line up with the item's text rather than its bullet or number.
struct DocumentText: View {
    let blocks: [DocumentBlock]
    let font: Font
    let scale: CGFloat
    let bodySize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                block(item)
                    .padding(.top, index == 0 ? 0 : spacing(before: index))
            }
        }
        .font(font)
        .textSelection(.enabled)
    }

    private struct Item {
        let block: DocumentBlock
        let marker: String?
    }

    private var items: [Item] {
        var number = 0
        return blocks.enumerated().map { index, block in
            number = block.type == .number ? (index > 0 && blocks[index - 1].type == .number ? number + 1 : 1) : 0
            switch block.type {
            case .bullet: return Item(block: block, marker: "•")
            case .number: return Item(block: block, marker: "\(number).")
            default: return Item(block: block, marker: nil)
            }
        }
    }

    private func spacing(before index: Int) -> CGFloat {
        let bothList = blocks[index - 1].type.isList && blocks[index].type.isList
        return (bothList ? 6 : bodySize * 0.9) * scale
    }

    @ViewBuilder
    private func block(_ item: Item) -> some View {
        if item.block.type == .rule {
            Divider().padding(.vertical, 6)
        } else if let marker = item.marker {
            HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                Text(marker)
                    .monospacedDigit()
                    .frame(minWidth: bodySize * 1.3 * scale, alignment: .trailing)
                    .accessibilityHidden(item.block.type == .bullet)
                text(for: item.block)
            }
        } else {
            text(for: item.block)
        }
    }

    private func text(for block: DocumentBlock) -> some View {
        Text(RichText.linkingHashtags(in: RichText.displayString(from: [DocumentBlock(type: .paragraph, runs: block.runs)])))
            .lineSpacing(5 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EntryReflection: Identifiable {
    let date: String
    let text: String
    var id: String { date + text }
}

struct ReflectionSheet: View {
    let reflection: EntryReflection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(reflection.date)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    // Light Markdown: the reply bolds its closing question.
                    Text(AttributedString.journal(reflection.text))
                        .font(.system(.title3, design: .serif))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    Label("Written on this device by Apple Intelligence. Your entry wasn't sent anywhere.", icon: "slab-lock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Hashtags with a date (like the web's "Tags:"): tap to search, long-press for how long it had
/// been on this entry's day.
private struct DatedHashtagRow: View {
    let hashtags: [DatedHashtag]
    @Environment(\.openURL) private var openURL

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(hashtags) { hashtag in
                Button {
                    search(hashtag)
                } label: {
                    Label("#\(hashtag.tag)", icon: "slab-hourglass")
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint.opacity(0.12), in: .capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .contextMenu {
                    Button { search(hashtag) } label: { Label("Search #\(hashtag.tag)", icon: "slab-search") }
                } preview: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("#\(hashtag.tag)")
                            .font(.headline)
                        Text(hashtag.age.prefix(1).uppercased() + hashtag.age.dropFirst())
                            .font(.system(.title3, design: .serif))
                        if let day = hashtag.day {
                            Text("#\(hashtag.tag) is dated \(day.formatted(.dateTime.month(.wide).day().year()))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(width: 280, alignment: .leading)
                }
                .accessibilityLabel("#\(hashtag.tag)")
                .accessibilityValue(hashtag.age)
            }
        }
    }

    private func search(_ hashtag: DatedHashtag) {
        if let url = URL(string: "\(RichText.hashtagScheme):\(hashtag.tag)") { openURL(url) }
    }
}

/// Swipe left on an entry: its actions as big buttons in a short sheet from the bottom.
private struct EntryActionsSheet: View {
    enum Action { case reflect, edit, delete, web }

    let entry: EntryDetail
    let canReflect: Bool
    let canEdit: Bool
    let perform: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.day?.long ?? entry.date)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            if canReflect {
                row("Reflect on This Entry", "slab-thought-bubble", .reflect)
            }
            if canEdit {
                row(entry.document != nil ? "Edit" : "Edit on dabble.me", "slab-edit", .edit)
                row("Delete", "slab-trash", .delete, role: .destructive)
            } else {
                row("Open on dabble.me", "safari", .web)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 12)
        .presentationDetents([.height(canEdit && canReflect ? 280 : 230)])
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

/// Pull down on an entry to get a reflection; without Apple Intelligence there's nothing to pull for.
private struct PullToReflect: ViewModifier {
    let action: (() async -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}
