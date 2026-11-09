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
    /// How far the entry follows a swipe left (≤ 0); past `swipeThreshold` it opens the actions.
    @State private var swipeOffset: CGFloat = 0
    private let swipeThreshold: CGFloat = 80
    /// Tapping the title switches between the date and how long ago it was (remembered).
    @AppStorage("entry.showsRelativeDate") private var showsRelativeDate = false
    @State private var hideHUD: Task<Void, Never>?
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif

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
                        .offset(x: swipeOffset)
                }
                .simultaneousGesture(swipeForActions)
                .overlay(alignment: .trailing) { swipeHint }
                .modifier(PullToReflect(action: canReflect(entry) ? { await reflect(on: entry) } : nil))
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
                                  canEdit: model.me?.canEdit == true,
                                  canDelete: model.me?.mayDelete == true) { action in
                    showingActions = false
                    switch action {
                    case .reflect: Task { await reflect(on: entry) }
                    case .edit: if entry.document != nil { editing = true } else { openURL(entry.webUrl) }
                    case .delete: confirmingDelete = true
                    case .web: openURL(entry.webUrl)
                    case .search(let tag): if let url = URL(string: "\(RichText.hashtagScheme):\(tag)") { openURL(url) }
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
        .sensoryFeedback(.impact(weight: .light), trigger: swipeArmed) { _, armed in armed }
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

    /// Swipe left anywhere on the entry for its actions (a right swipe is iOS's "go back"). The
    /// text follows your finger and the Actions bolt comes in from the right; let go past the
    /// threshold to open them.
    private var swipeForActions: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                let dx = value.translation.width, dy = value.translation.height
                guard dx < 0, abs(dy) < abs(dx) * 0.5 else {
                    if swipeOffset != 0 { withAnimation(.spring(duration: 0.25)) { swipeOffset = 0 } }
                    return
                }
                // 1:1 up to the threshold, then it resists.
                let pull = -dx
                swipeOffset = -(pull <= swipeThreshold ? pull : swipeThreshold + (pull - swipeThreshold) * 0.35)
            }
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                if dx < -swipeThreshold, abs(dy) < abs(dx) * 0.5 { showingActions = true }
                withAnimation(.spring(duration: 0.3)) { swipeOffset = 0 }
            }
    }

    private var swipeArmed: Bool { -swipeOffset >= swipeThreshold }

    /// The bolt that slides in from the right edge as the entry is swiped.
    @ViewBuilder
    private var swipeHint: some View {
        if swipeOffset < -4 {
            let progress = min(1, -swipeOffset / swipeThreshold)
            VStack(spacing: 6) {
                appIcon("slab-bolt")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(swipeArmed ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: 44, height: 44)
                    .background(swipeArmed ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.15)), in: .circle)
                Text("Actions")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(swipeArmed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .scaleEffect(0.6 + 0.4 * progress)
            .opacity(progress)
            .frame(width: max(0, min(-swipeOffset, 120)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(.easeOut(duration: 0.15), value: swipeArmed)
        }
    }

    @ViewBuilder
    private func actionButtons(for entry: EntryDetail) -> some View {
            // Reflect is pull-down (and the swipe-left sheet), not in this menu.
            if model.me?.canEdit == true {
                if entry.document != nil {
                    Button { editing = true } label: { Label("Edit", icon: "slab-edit") }
                } else {
                    // Formatting the app can't represent (styles, quotes, images) stays web-only so nothing gets lost.
                    Button("Edit on dabble.me", systemImage: "safari") { openURL(entry.webUrl) }
                }
            }
            // Free accounts can delete, not edit.
            if model.me?.mayDelete == true {
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", icon: "slab-trash") }
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

    private func reflect(on entry: EntryDetail) async {
        isReflecting = true
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
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17

    private var bodyFont: Font { .system(size: bodySize * textSize.scale, design: fontStyle.design) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let document = entry.document {
                // Selectable across paragraphs (SwiftUI's selection stops at each paragraph).
                SelectableDocumentText(blocks: document, fontSize: bodySize * textSize.scale,
                                       design: fontStyle.uiDesign, lineSpacing: 5 * textSize.scale)
            } else if !entry.bodyText.isEmpty {
                Text(RichText.linkingURLs(in: RichText.linkingHashtags(in: AttributedString.journal(entry.bodyText))))
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
                    SongList(songs: entry.songs)
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
                    // Two short lines with the lock centered beside both.
                    HStack(spacing: 12) {
                        appIcon("slab-lock")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text("Written on this device by Apple Intelligence.\nYour entry wasn't sent anywhere.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .padding(.top, 8)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A short reflection doesn't bounce, so pulling down drags the sheet closed.
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Hashtags with a date (like the web's "Tags:"): each pill shows how long it had been on this
/// entry's day ("3 years and 5 months"). Tap to search; long-press for the tag's date.
struct DatedHashtagRow: View {
    let hashtags: [DatedHashtag]
    @Environment(\.openURL) private var openURL

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(hashtags) { hashtag in
                Button {
                    search(hashtag)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("#\(hashtag.tag)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.tint)
                        Text(Self.shortAge(hashtag.age))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.tint.opacity(0.12), in: .rect(cornerRadius: 12))
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

    /// "3 years and 4 months since entry" → "3 years and 4 months" (the pill is under the entry).
    static func shortAge(_ age: String) -> String {
        let short = age.replacingOccurrences(of: " since entry", with: "")
        return short.prefix(1).uppercased() + short.dropFirst()
    }
}


/// Pull down on an entry to get a reflection; without Apple Intelligence there's nothing to pull for.
/// Not `.refreshable`: its bare spinner reads as "reload". The pull says what it does ("Pull to
/// reflect…", then "Release to reflect" with a tap of haptics) and fires when you let go.
private struct PullToReflect: ViewModifier {
    let action: (() async -> Void)?
    @State private var pull: CGFloat = 0
    @State private var isRunning = false
    private let threshold: CGFloat = 90

    private var armed: Bool { pull >= threshold }

    func body(content: Content) -> some View {
        if let action {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    -(geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, overscroll in
                    pull = max(0, overscroll)
                }
                .onScrollPhaseChange { old, new in
                    guard old == .interacting, new != .interacting, armed, !isRunning else { return }
                    isRunning = true
                    Task {
                        await action()
                        isRunning = false
                    }
                }
                .overlay(alignment: .top) {
                    if pull > 8, !isRunning {
                        Label(armed ? "Release to reflect" : "Pull to reflect on this entry", icon: "slab-sparkles")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(armed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .opacity(min(1, (pull - 8) / 40))
                            .frame(height: min(pull, threshold))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, isArmed in isArmed }
                .animation(.easeOut(duration: 0.15), value: armed)
        } else {
            content
        }
    }
}
