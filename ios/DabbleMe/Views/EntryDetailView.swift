import SwiftUI

/// One entry. Pull down at the top for the next (newer) day with an entry, pull up at the
/// bottom for the previous one, like pulling the days into view. Pinch to change text size.
struct EntryDetailView: View {
    let entryID: Int
    var sequence: [EntryNeighbour]? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var currentID: Int?
    @State private var entry: EntryDetail?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var pull = Pull.none
    /// The pull that was armed while the finger was down. Kept separately because the scroll
    /// view starts bouncing back before the release reaches us, which disarms `pull`.
    @State private var armedPull = Pull.none
    @State private var isInteracting = false
    /// Which edges the entry was resting at (both for a short entry), and so which ways a flick
    /// that started there may move: if you let go early and the bounce carries past the
    /// threshold, that still moves. A fast scroll that only hits the edge partway doesn't.
    @State private var restingEdges: Edge.Set = []
    @State private var flickEdges: Edge.Set = []
    @State private var arrivalEdge = Edge.bottom
    @State private var isMoving = false
    @State private var pinchStart: ReadingTextSize?
    @State private var textSizeHUD: String?
    @State private var reflection: EntryReflection?
    @State private var isReflecting = false
    /// Tapping the title switches between the date and how long ago it was (remembered).
    @AppStorage("entry.showsRelativeDate") private var showsRelativeDate = false
    @State private var hideHUD: Task<Void, Never>?
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard

    private var id: Int { currentID ?? entryID }

    /// How far past the top/bottom the reader has pulled; `armed` means releasing will move.
    enum Pull: Equatable {
        case none
        case newer(armed: Bool)
        case older(armed: Bool)
    }

    private static let pullThreshold: CGFloat = 70

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
                        .id(entry.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: arrivalEdge).combined(with: .opacity),
                            removal: .move(edge: arrivalEdge == .top ? .bottom : .top).combined(with: .opacity)
                        ))
                }
                .scrollBounceBehavior(.always)
                .onScrollGeometryChange(for: Edge.Set.self, of: Self.restingEdges(for:)) { _, edges in
                    if !isInteracting { restingEdges = edges }
                }
                .onScrollGeometryChange(for: Pull.self, of: Self.pull(for:)) { _, newValue in
                    pull = newValue
                    // While the finger is down, track whether it's past the threshold right now.
                    // Once armed (you feel the tick), a drag stays armed unless it goes back to
                    // the edge; easing off a little before letting go still moves.
                    if isInteracting {
                        if newValue.isArmed { armedPull = newValue } else if newValue == .none { armedPull = .none }
                    } else if newValue.isArmed, flickEdges.contains(newValue.edge) {
                        flickEdges = []
                        armedPull = newValue
                        releasePull(from: entry)
                    }
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    if newPhase == .interacting {
                        isInteracting = true
                        armedPull = .none
                        flickEdges = restingEdges
                    } else if oldPhase == .interacting {
                        isInteracting = false
                        releasePull(from: entry)
                    } else if newPhase == .idle {
                        flickEdges = []
                    }
                }
                .overlay(alignment: .top) {
                    if case .newer(let armed) = pull {
                        let armed = armed || armedPull.isArmed
                        PullHint(text: hintText(for: neighbours(of: entry).newer, armed: armed, newer: true), systemImage: "arrow.down", armed: armed)
                    }
                }
                .overlay(alignment: .bottom) {
                    if case .older(let armed) = pull {
                        let armed = armed || armedPull.isArmed
                        PullHint(text: hintText(for: neighbours(of: entry).older, armed: armed, newer: false), systemImage: "arrow.up", armed: armed)
                            .padding(.bottom, 70)
                    }
                }
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
        .sensoryFeedback(.impact(weight: .light), trigger: pull.isArmed) { _, armed in armed }
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
            if JournalIntelligence.isEnabled(for: model.me), !entry.bodyText.isEmpty {
                Button("Reflect on This Entry", systemImage: "sparkles") { Task { await reflect(on: entry) } }
                    .disabled(isReflecting)
            }
            if model.me?.canEdit == true {
                if entry.document != nil {
                    Button("Edit", systemImage: "pencil") { editing = true }
                } else {
                    // Formatting the app can't represent (styles, quotes, images) stays web-only so nothing gets lost.
                    Button("Edit on dabble.me", systemImage: "safari") { openURL(entry.webUrl) }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } else {
                Button("Open on dabble.me", systemImage: "safari") { openURL(entry.webUrl) }
            }
        } label: {
            Label("Entry Actions", systemImage: "ellipsis.circle")
        }
    }

    /// Tap: the date or how long ago it was. Long-press: a reflection (PRO, Apple Intelligence).
    private func dateTitle(for entry: EntryDetail) -> some View {
        let full = entry.day?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()) ?? entry.date
        let today = model.today?.day ?? JournalDay(localDate: .now)
        let relative = entry.day.map { $0.relative(to: today) } ?? full
        let canReflect = JournalIntelligence.isEnabled(for: model.me) && !entry.bodyText.isEmpty
        return Text(showsRelativeDate ? relative : full)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .contentTransition(.opacity)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(.rect)
            .onTapGesture { showsRelativeDate.toggle() }
            .onLongPressGesture(minimumDuration: 0.4) {
                guard canReflect, !isReflecting else { return }
                Task { await reflect(on: entry) }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: isReflecting) { _, started in started }
            .accessibilityElement()
            .accessibilityLabel(entry.day?.long ?? entry.date)
            .accessibilityValue(relative)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Switches between the date and how long ago it was")
            .accessibilityAction { showsRelativeDate.toggle() }
            .accessibilityActions {
                if canReflect {
                    Button("Reflect on This Entry") { Task { await reflect(on: entry) } }
                }
            }
            .animation(.easeOut(duration: 0.15), value: showsRelativeDate)
    }

    private func reflect(on entry: EntryDetail) async {
        isReflecting = true
        defer { isReflecting = false }
        do {
            let recent = (try? await model.recentEntries())?.filter { $0.id != entry.id }.prefix(3).map(\.excerpt) ?? []
            let text = try await JournalIntelligence.reflection(on: entry.bodyText, date: entry.day?.long ?? entry.date,
                                                                firstName: model.me?.firstName, recent: Array(recent))
            reflection = EntryReflection(date: entry.day?.long ?? entry.date, text: text)
        } catch is CancellationError {
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Pulling between days

    private static func restingEdges(for geometry: ScrollGeometry) -> Edge.Set {
        let minOffset = -geometry.contentInsets.top
        let maxOffset = max(minOffset, geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height)
        var edges: Edge.Set = []
        if geometry.contentOffset.y <= minOffset + 8 { edges.insert(.top) }
        if geometry.contentOffset.y >= maxOffset - 8 { edges.insert(.bottom) }
        return edges
    }

    private static func pull(for geometry: ScrollGeometry) -> Pull {
        let top = -(geometry.contentOffset.y + geometry.contentInsets.top)
        let maxOffset = max(-geometry.contentInsets.top,
                            geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height)
        let bottom = geometry.contentOffset.y - maxOffset
        if top > 24 { return .newer(armed: top > pullThreshold) }
        if bottom > 24 { return .older(armed: bottom > pullThreshold) }
        return .none
    }

    /// The entries before and after this one: by date, or within the search results it was opened from.
    private func neighbours(of entry: EntryDetail) -> (newer: EntryNeighbour?, older: EntryNeighbour?) {
        guard let sequence, let index = sequence.firstIndex(where: { $0.id == entry.id }) else {
            return (entry.nextEntry, entry.previousEntry)
        }
        return (index > 0 ? sequence[index - 1] : nil, index + 1 < sequence.count ? sequence[index + 1] : nil)
    }

    private func hintText(for neighbour: EntryNeighbour?, armed: Bool, newer: Bool) -> String {
        guard let day = neighbour?.day else {
            if sequence != nil { return newer ? "This is the first result" : "This is the last result" }
            return newer ? "This is your newest entry" : "This is your first entry"
        }
        let date = day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
        return armed ? "Release for \(date)" : "Pull for \(date)"
    }

    private func releasePull(from entry: EntryDetail) {
        defer { armedPull = .none }
        switch armedPull {
        case .newer(armed: true): move(to: neighbours(of: entry).newer, arrivingFrom: .top)
        case .older(armed: true): move(to: neighbours(of: entry).older, arrivingFrom: .bottom)
        default: break
        }
    }

    private func move(to neighbour: EntryNeighbour?, arrivingFrom edge: Edge) {
        guard let neighbour, !isMoving else { return }
        isMoving = true
        Task {
            defer { isMoving = false }
            do {
                let next = try await model.entry(id: neighbour.id)
                arrivalEdge = edge
                withAnimation(.snappy(duration: 0.35)) {
                    currentID = next.id
                    entry = next
                }
            } catch is CancellationError {
            } catch {
                actionError = error.localizedDescription
            }
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

private extension EntryDetailView.Pull {
    var isArmed: Bool {
        switch self {
        case .newer(let armed), .older(let armed): armed
        case .none: false
        }
    }

    /// Pulling down past the top shows newer entries; pulling up past the bottom, older ones.
    var edge: Edge.Set {
        switch self {
        case .newer: .top
        case .older: .bottom
        case .none: []
        }
    }
}

private struct PullHint: View {
    let text: String
    let systemImage: String
    let armed: Bool

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(armed ? .semibold : .regular))
            .foregroundStyle(armed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: .capsule)
            .padding(.top, 8)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: armed)
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
                            Label(song.label, systemImage: "music.note")
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

private struct ReflectionSheet: View {
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
                    Label("Written on this device by Apple Intelligence. Your entry wasn't sent anywhere.", systemImage: "lock")
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
                    Label("#\(hashtag.tag)", systemImage: "calendar")
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint.opacity(0.12), in: .capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .contextMenu {
                    Button("Search #\(hashtag.tag)", systemImage: "magnifyingglass") { search(hashtag) }
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
