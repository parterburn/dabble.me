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
    @State private var isDeleting = false
    @State private var pinchStart: ReadingTextSize?
    @State private var textSizeHUD: String?
    @State private var reflection: EntryReflection?
    @State private var showingActions = false
    /// How far the entry follows a swipe left (≤ 0); past `swipeThreshold` it opens the actions.
    @State private var swipeOffset: CGFloat = 0
    private let swipeThreshold: CGFloat = 80
    /// Tapping the title switches between the date and how long ago it was (remembered).
    @AppStorage("entry.showsRelativeDate") private var showsRelativeDate = false
    @State private var hideHUD: Task<Void, Never>?
    /// The song in the player under the entry (its first, until another is tapped), how many
    /// times a song's been tapped to play (none: the player only shows it), and whether the
    /// player's been swiped away.
    @State private var song: Song?
    @State private var songPlays = 0
    @State private var playerHidden = false
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif

    /// The entry shown: the one opened, or the one it was merged into when its date was changed
    /// to a day that had one.
    private var id: Int { entry?.id ?? entryID }

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    EntryBody(entry: entry, song: playerHidden ? nil : song, play: play)
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
                // An entry with a song has Spotify's player under it, as the Playlist does. It
                // doesn't start by itself: a tap on a song, or on the player's own button, does.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let song, !playerHidden {
                        SongPlayerBar(song: song, plays: songPlays, openPlaylist: {
                            model.selectedTab = .journal
                            model.journalModeRequest = .playlist
                        }) { playerHidden = true }
                    }
                }
                .animation(.snappy(duration: 0.25), value: playerHidden)
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
        .slabBackButton()
        .toolbar {
            if let entry {
                ToolbarItem(placement: .principal) { dateTitle(for: entry) }
                ToolbarItem(placement: .primaryAction) { editButton(for: entry) }
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
                    case .edit: if entry.document != nil { editing = true } else { openURL(entry.webEditURL) }
                    case .delete: Task { await delete() }
                    case .web: openURL(entry.webUrl)
                    case .search(let tag): if let url = URL(string: "\(RichText.hashtagScheme):\(tag)") { openURL(url) }
                    }
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let entry {
                ComposeView(mode: .edit(entry)) { self.entry = $0 }
            }
        }
        .sheet(item: $reflection) { reflection in
            ReflectionSheet(reflection: reflection) { self.entry = $0 }
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
        // The first song is the one shown, and again if an edit takes the shown one away.
        .onChange(of: entry?.songs, initial: true) { _, songs in
            guard let songs, song.map(songs.contains) != true else { return }
            song = songs.first { $0.trackID != nil }
            songPlays = 0
        }
        .task(id: entry?.imageProcessing) {
            // Swap the placeholder for the finished photo/collage as soon as it's ready.
            while entry?.imageProcessing == true, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await load()
            }
        }
    }

    /// A tap on one of the entry's songs: it takes the player (one song at a time) and starts.
    private func play(_ tapped: Song) {
        guard tapped.trackID != nil else { openURL(tapped.spotifyUrl); return }
        song = tapped
        songPlays += 1
        playerHidden = false
    }

    /// Edit goes straight into editing; Delete and Reflect are in the swipe-left Actions.
    @ViewBuilder
    private func editButton(for entry: EntryDetail) -> some View {
        if model.me?.canEdit == true {
            // Tap to edit; touch and hold for the entry's Actions (Reflection, Delete, its tags).
            // Not a Button: in the toolbar a Button becomes a UIKit bar button, which never sees a
            // long press. This view keeps its own gestures (a hold doesn't also tap).
            appIcon("slab-edit")
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .onTapGesture {
                    // Formatting the app can't represent (styles, quotes, images) stays web-only so nothing gets lost.
                    if entry.document != nil { editing = true } else { openURL(entry.webEditURL) }
                }
                .onLongPressGesture(minimumDuration: 0.45) { showingActions = true }
                .accessibilityElement()
                .accessibilityLabel("Edit Entry")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { if entry.document != nil { editing = true } else { openURL(entry.webEditURL) } }
                .accessibilityAction(named: "More Actions") { showingActions = true }
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

    /// Tap: the date or how long ago it was.
    private func dateTitle(for entry: EntryDetail) -> some View {
        let full = entry.day?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()) ?? entry.date
        let today = model.today?.day ?? JournalDay(localDate: .now)
        let relative = entry.day.map { $0.relative(to: today) } ?? full
        return Text(showsRelativeDate ? relative : full)
            .font(.headline)
            .foregroundStyle(.tint) // olive, like the dates over entries elsewhere
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

    /// The reflection's sheet opens right away, reflecting inside it, so you can see where it'll appear.
    private func reflect(on entry: EntryDetail) async {
        guard reflection == nil else { return }
        let pending = EntryReflection(date: model.dateLine(for: entry.day, fallback: entry.date), entryText: entry.bodyText,
                                      entryID: entry.id, document: entry.document)
        reflection = pending
        do {
            let text = try await model.reflection(on: entry).text
            if reflection?.id == pending.id { reflection?.text = text }
        } catch {
            if reflection?.id == pending.id { reflection = nil }
            if !(error is CancellationError) { actionError = error.localizedDescription }
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
    /// The song in the player, and what a tap on a song does.
    var song: Song?
    var play: ((Song) -> Void)?
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17

    private var bodyFont: Font { .system(size: bodySize * textSize.scale, design: fontStyle.design) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Dated #tags and Spotify links at the end of the entry aren't shown twice: their pills
            // and the songs are right under it.
            let pilled = (entry.datedHashtags ?? []).map(\.tag)
            if let document = entry.document {
                // Selectable across paragraphs (SwiftUI's selection stops at each paragraph).
                SelectableDocumentText(blocks: RichText.droppingTrailing(hashtags: pilled, songLinks: !entry.songs.isEmpty, from: document), fontSize: bodySize * textSize.scale,
                                       design: fontStyle.uiDesign, lineSpacing: 5 * textSize.scale)
            } else if !entry.bodyText.isEmpty {
                Text(RichText.linkingURLs(in: RichText.linkingHashtags(in: AttributedString.journal(RichText.droppingTrailing(hashtags: pilled, songLinks: !entry.songs.isEmpty, from: entry.bodyText)))))
                    .font(bodyFont)
                    .lineSpacing(5 * textSize.scale)
                    .textSelection(.enabled)
            }

            if let dated = entry.datedHashtags, !dated.isEmpty {
                DatedHashtagRow(hashtags: dated)
            }

            // The music icon says what they are; no "Songs" heading.
            if !entry.songs.isEmpty {
                SongList(songs: entry.songs, selected: song, select: play)
            }

            // Text first: Dabble Me is about the writing; photos follow it.
            if entry.imageProcessing || entry.imageURL != nil {
                EntryPhoto(url: entry.imageURL, isProcessing: entry.imageProcessing, day: entry.day)
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
        let numbers = RichText.listNumbers(for: blocks)
        return blocks.enumerated().map { index, block in
            switch block.type {
            case .bullet: Item(block: block, marker: "•")
            case .number: Item(block: block, marker: "\(numbers[index]).")
            default: Item(block: block, marker: nil)
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
            // A list inside another starts under its item's text.
            .padding(.leading, CGFloat(item.block.depth) * (bodySize * 1.3 + 6) * scale)
        } else {
            text(for: item.block)
        }
    }

    private func text(for block: DocumentBlock) -> some View {
        Text(RichText.linkingURLs(in: RichText.linkingHashtags(in: RichText.displayString(from: [DocumentBlock(type: .paragraph, runs: block.runs)]))))
            .lineSpacing(5 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A reflection's sheet: open while Apple Intelligence writes it (`text` is nil until then).
struct EntryReflection: Identifiable {
    let id = UUID()
    var date: String
    /// The entry's text, for chatting about it after the reflection.
    var entryText = ""
    /// The entry and its editable content, so a summary of the chat can be added to it.
    var entryID: Int?
    var document: [DocumentBlock]?
    var text: String?
}

struct ReflectionSheet: View {
    let reflection: EntryReflection
    /// The entry after a summary of the chat was added to it.
    var onEntryUpdated: (EntryDetail) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @State private var summary = SummaryPhase.offer

    private enum SummaryPhase: Equatable {
        case offer, working, preview(String), saving(String), added, failed(String), dismissed
    }
    /// After the reflection, a chat about the entry (on the device, never saved).
    @State private var chat: ReflectionChat?
    @State private var draft = ""
    @State private var detent = PresentationDetent.medium
    @FocusState private var replying: Bool

    var body: some View {
        // Laid out like Random Memory: the title and the X across the top, then the text.
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Reflection", icon: "slab-sparkles")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                SheetCloseButton()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !reflection.date.isEmpty {
                            Text(reflection.date)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                        if let text = reflection.text {
                            // Light Markdown: the reply bolds its closing question.
                            Text(AttributedString.journal(text))
                                .font(.system(.title3, design: .serif))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .transition(.opacity)
                            if let chat {
                                ForEach(chat.messages) { message in
                                    ChatBubble(message: message, isReplying: chat.isReplying && message == chat.messages.last)
                                        .id(message.id)
                                }
                                // After the first answer and reply: offer to keep it in the entry.
                                if canAddSummary, chat.messages.count >= 2, !chat.isReplying || summary != .offer {
                                    summaryOffer(chat)
                                }
                            }
                            privacyNote(chat?.messages.isEmpty == false
                                ? "On this device, and not saved anywhere.\nClosing this forgets the conversation."
                                : "Written on this device by Apple Intelligence.\nYour entry wasn't sent anywhere.")
                                .id("bottom")
                        } else {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.large)
                                Text("Generating…")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 160)
                            .accessibilityElement(children: .combine)
                            privacyNote("Apple Intelligence is writing this on your device.\nYour entry isn't sent anywhere.")
                        }
                    }
                    .padding(.bottom)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // A short reflection doesn't bounce, so pulling down drags the sheet closed.
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .animation(.easeOut(duration: 0.25), value: reflection.text)
                .onChange(of: chat?.messages.last?.text) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: summary) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                // Starting a reply: once the sheet has grown and the keyboard is up, the end of
                // the reflection (its question) is in view, not scrolled out above the field.
                .onChange(of: replying) { _, typing in
                    guard typing else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
            if reflection.text != nil, !reflection.entryText.isEmpty {
                replyField
            }
        }
        .padding([.horizontal, .top], 20)
        .padding(.bottom, reflection.text != nil ? 8 : 0)
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large], selection: $detent)
        // Room to read the conversation while typing.
        .onChange(of: replying) { _, typing in if typing { withAnimation { detent = .large } } }
    }

    /// Answer the reflection's question and keep talking it through.
    private var replyField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Reply to keep talking it through…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($replying)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 20))
                .accessibilityIdentifier("ReflectionReply")
                .onSubmit(send)
            Button(action: send) {
                appIcon("slab-send")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat?.isReplying == true)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            .accessibilityLabel("Send")
        }
    }

    /// Only where the writer can edit this entry in the app (PRO, and formatting the app can keep).
    private var canAddSummary: Bool {
        model.me?.canEdit == true && reflection.entryID != nil && reflection.document != nil
    }

    @ViewBuilder
    private func summaryOffer(_ chat: ReflectionChat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch summary {
            case .offer:
                Text("If you'd like to keep any of this, I can sum up our conversation and add it to this day's entry.")
                    .foregroundStyle(.secondary)
                Button {
                    replying = false // the keyboard down, so the summary shows
                    Task { await summarize(chat) }
                } label: {
                    Label("Sum Up & Add to Entry", icon: "slab-sparkles")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Summing up…").foregroundStyle(.secondary)
                }
            case .preview(let text), .saving(let text):
                // As it'll read in the entry.
                (Text("Reflection: ").bold() + Text(text))
                    .font(.system(.body, design: .serif))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.tint.opacity(0.08), in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("ReflectionSummary")
                HStack(spacing: 10) {
                    Button("Add to Entry") { Task { await addToEntry(text) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(summary == .saving(text))
                    Button("Not Now") { summary = .dismissed }
                        .buttonStyle(.bordered)
                }
                .buttonBorderShape(.capsule)
            case .added:
                Label("Added to this day's entry.", icon: "slab-check")
                    .foregroundStyle(.tint)
            case .failed(let message):
                Text(message).foregroundStyle(.secondary)
                Button("Try Again") { Task { await summarize(chat) } }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            case .dismissed:
                EmptyView()
            }
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .animation(.easeOut(duration: 0.2), value: summary)
    }

    private func summarize(_ chat: ReflectionChat) async {
        summary = .working
        do {
            let text = try await JournalIntelligence.chatSummary(entry: reflection.entryText, conversation: chat.messages)
            summary = .preview(text)
        } catch {
            summary = .failed(error.localizedDescription)
        }
    }

    /// Adds the summary at the end of the entry as its own paragraph, starting "Reflection:" in
    /// bold, through the usual edit.
    private func addToEntry(_ text: String) async {
        guard let id = reflection.entryID, let document = reflection.document else { return }
        summary = .saving(text)
        do {
            let paragraph = DocumentBlock.paragraph(DocumentRun("Reflection:", bold: true), DocumentRun(" " + text))
            let updated = try await model.updateEntry(id: id, document: document + [paragraph])
            onEntryUpdated(updated)
            summary = .added
        } catch {
            summary = .failed(error.localizedDescription)
        }
    }

    private func send() {
        guard let text = reflection.text else { return }
        let message = draft
        draft = ""
        // The keyboard commits a pending autocorrection as Send is tapped, which puts the text
        // back: clear it again once that's happened.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            draft = ""
        }
        let chat = chat ?? ReflectionChat(entry: reflection.entryText, date: reflection.date, reflection: text, firstName: model.me?.firstName)
        self.chat = chat
        Task { await chat.send(message) }
    }

    /// Two short lines with the lock centered beside both.
    private func privacyNote(_ text: String) -> some View {
        HStack(spacing: 12) {
            appIcon("slab-lock")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .padding(.top, 8)
    }
}

/// One turn of the reflection chat: the writer's on the right in a tinted bubble, the reply on
/// the left in the reflection's serif type (a spinner while it starts).
private struct ChatBubble: View {
    let message: ReflectionChat.Message
    let isReplying: Bool

    var body: some View {
        if message.fromWriter {
            Text(message.text)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.tint.opacity(0.14), in: .rect(cornerRadius: 18))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
                .textSelection(.enabled)
        } else if message.text.isEmpty, isReplying {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Light Markdown, like the reflection: it bolds its question too.
            Text(AttributedString.journal(message.text))
                .font(.system(.title3, design: .serif))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityIdentifier("ReflectionChatReply")
        }
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
                    HashtagPill(tag: hashtag.tag, age: hashtag.age)
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

/// The app's #tag pill: the tag in olive on a light olive card, with its age beside it for a
/// dated tag ("#Leo  3 years and 4 months"), on one line. Under entries, in the Actions sheet, and
/// anywhere tags show. One too long for the space it's given scrolls sideways inside its card.
struct HashtagPill: View {
    let tag: String
    /// "3 years and 4 months since entry", or nil for a tag without a date.
    var age: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line
            ScrollView(.horizontal) { line }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
        }
        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private var line: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("#\(tag)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tint)
            if let age {
                Text(Self.shortAge(age))
                    .font(.footnote)
                    .foregroundStyle(.primary.opacity(0.72)) // stronger than .secondary on the tint
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
