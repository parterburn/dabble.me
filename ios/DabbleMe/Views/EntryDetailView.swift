import SwiftUI

/// One entry. Pinch to change text size; pull down for a reflection (PRO, Apple Intelligence);
/// swipe left for its actions (reflect, edit, delete).
struct EntryDetailView: View {
    let entryID: Int

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.backTrail) private var backTrail
    @Environment(\.openURL) private var openURL
    @State private var entry: EntryDetail?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var editing = false
    @State private var isDeleting = false
    @State private var isStepping = false
    @State private var pinchStart: ReadingTextSize?
    @State private var textSizeHUD: String?
    @State private var reflection: EntryReflection?
    @State private var showingActions = false
    /// How far the entry follows a swipe left (≤ 0); past `swipeThreshold` it opens the actions.
    @State private var swipeOffset: CGFloat = 0
    private let swipeThreshold: CGFloat = 80
    /// Tapping the title switches between the date and how long ago it was (remembered).
    /// The title says how long ago the entry was, in place of its date: while the page is
    /// scrolled down (back at the top, it's the date again), and when the date's tapped.
    @State private var showsRelativeDate = false
    /// The floating actions are out of the way: while scrolling down through a long entry.
    @State private var actionsHidden = false
    /// How tall the entry's card is, to know when its foot has come into view.
    @State private var cardHeight: CGFloat = 0
    @State private var hideHUD: Task<Void, Never>?
    /// The song for the player under the entry (the one tapped), how many times a song's been
    /// tapped to play, and whether the player's out of sight: it is until a song is tapped
    /// (nothing is asked of Spotify just for opening an entry), and again once swiped away.
    @State private var song: Song?
    @State private var songPlays = 0
    @State private var playerHidden = true
    /// The entry's calendar day in other years: On This Day, under it.
    @State private var sameDay: SameDayEntries?
    /// Scrolled down into On This Day (its heading has gone under the bar), and an entry opened from it.
    @State private var reading = ReadingSpot()
    @State private var opened: EntryRoute?
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif

    /// Other years' entries follow the one that's open.
    private var hasOnThisDay: Bool { (sameDay?.count ?? 0) > 0 }

    /// The entry shown: the one opened, or the one it was merged into when its date was changed
    /// to a day that had one.
    private var id: Int { entry?.id ?? entryID }

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // The entry that was opened is on the page's own background (white, in
                        // light mode), from the bar down to its last line or its photo: no card
                        // around it. Other years' entries, when there are any, follow on Paper.
                        EntryBody(entry: entry, song: playerHidden ? nil : song, play: play)
                            .frame(maxWidth: 680, alignment: .leading)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .contentShape(.rect)
                            .simultaneousGesture(pinchToResize)
                            // The swipe for Actions is the entry's own: it starts on its card,
                            // not on On This Day under it.
                            .simultaneousGesture(swipeForActions)
                            .offset(x: swipeOffset)
                            // (Behind the swipe, not moved by it.) Its background runs on above
                            // the entry too, under the bar and when the page is pulled down.
                            .background(Color(.systemBackground))
                            .background(alignment: .top) {
                                Color(.systemBackground).frame(height: 1200).offset(y: -1200)
                            }
                            // A soft line where the entry ends and On This Day begins.
                            .overlay(alignment: .bottom) {
                                if hasOnThisDay { Rectangle().fill(.quaternary).frame(height: 1) }
                            }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                            // The bolt the swipe brings in, beside the card: level with its
                            // middle, or with the middle of what shows of a card taller than
                            // the screen.
                            .overlay(alignment: .trailing) {
                                swipeHint.visualEffect { [height = cardHeight] content, proxy in
                                    let middle = proxy.size.height / 2
                                    guard let visible = proxy.bounds(of: .scrollView) else { return content.offset(y: 0) }
                                    let top = max(middle - height / 2, visible.minY), bottom = min(middle + height / 2, visible.maxY)
                                    return content.offset(y: bottom > top ? (top + bottom) / 2 - middle : 0)
                                }
                            }
                        if let sameDay, sameDay.count > 0 {
                            SameDaySection(entry: entry, sameDay: sameDay, reading: reading,
                                           today: model.today?.day ?? JournalDay(localDate: .now)) { opened = EntryRoute(id: $0) }
                                // (Each of its rows: from the leading edge of the column, as
                                // the entry is. Without the alignment its heading sat centered.)
                                .frame(maxWidth: 680, alignment: .leading)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    // Room for the last lines to scroll clear of the floating actions.
                    .padding(.bottom, 64)
                }
                // Under and after the entry: Paper when On This Day follows, so the two read
                // apart; with nothing after the entry, the page's own background all the way
                // down.
                .background(hasOnThisDay ? Color("Paper") : Color(.systemBackground))
                // The floating actions step aside while a long entry is scrolled down through,
                // and come back on the way up, at the entry's foot and at the page's.
                .onScrollGeometryChange(for: ScrollSpot.self) { geometry in
                    ScrollSpot(offset: geometry.contentOffset.y + geometry.contentInsets.top,
                               viewport: geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom,
                               content: geometry.contentSize.height)
                } action: { old, new in
                    let footInView = new.offset + new.viewport >= cardHeight && new.offset <= cardHeight
                    let atEnd = new.offset + new.viewport >= new.content - 8
                    let hidden: Bool
                    if new.offset <= 8 || footInView || atEnd {
                        hidden = false
                    } else if abs(new.offset - old.offset) < 2 {
                        hidden = actionsHidden
                    } else {
                        hidden = new.offset > old.offset
                    }
                    if hidden != actionsHidden { withAnimation(.snappy(duration: 0.25)) { actionsHidden = hidden } }
                    // Scrolled down, the title says how long ago the entry was; back at the top, its date.
                    let down = new.offset > 12
                    if down != (old.offset > 12), down != showsRelativeDate { showsRelativeDate = down }
                }
                // Under On This Day, the month of the entry being read stays at the top, as on
                // Today. It's part of the bar (not a header pinned in the page), so the bar's own
                // backing runs on under it and the two are one header.
                .modifier(TopBarExtension {
                    PinnedMonth(reading: reading, entries: sameDay?.entries ?? [], today: model.today?.day ?? JournalDay(localDate: .now))
                })
                .navigationDestination(item: $opened) {
                    EntryDetailView(entryID: $0.id)
                        .environment(\.backTrail, trail + [BackStep(title: entry.day?.formatted(.dateTime.month(.abbreviated).day().year()) ?? entry.date) { opened = nil }])
                }
                // Again when the entry moves to another day.
                .task(id: "\(entry.id)|\(entry.date)") {
                    let loaded = await model.sameDay(as: entry.id)
                    // Still this entry's (it can change while the answer's on its way).
                    if !Task.isCancelled, self.entry?.id == entry.id {
                        sameDay = loaded
                        // Only the months still listed (the day can change, and its list with it).
                        reading.passedMonths.formIntersection(loaded?.entries.map(\.id) ?? [])
                        if reading.passedMonths.isEmpty, loaded?.entries.isEmpty != false { reading.headingPassed = false }
                    }
                }
                .id(entry.id) // each entry starts at its top (the title's swipe steps between them)
                .overlay(alignment: .bottom) { floatingActions(for: entry) }
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
        // The arrow held: everywhere there is to go back to, once that's more than one place.
        .slabBackButton(trail: trail.reversed())
        .toolbar {
            if let entry {
                // Down in On This Day, the bar says so in place of the entry's date.
                ToolbarItem(placement: .principal) {
                    EntryTitle(reading: reading, hasOnThisDay: sameDay?.count ?? 0 > 0) {
                        onThisDayTitle
                    } date: {
                        dateTitle(for: entry)
                    }
                }
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
                    case .open: break // it's open
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
        // An edit that takes the playing song away takes the player with it.
        .onChange(of: entry?.songs) { _, songs in
            guard let song, songs?.contains(song) != true else { return }
            self.song = nil
            songPlays = 0
            playerHidden = true
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
                .onLongPressGesture(minimumDuration: 0.45) {
                    HoldHaptic.play()
                    showingActions = true
                }
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
    /// The pages behind this one, the furthest first: where the first entry was opened from
    /// (this one, when nothing's been handed down), then each entry opened from On This Day.
    private var trail: [BackStep] {
        guard backTrail.isEmpty else { return backTrail }
        let title = switch model.selectedTab {
        case .today: "Today"
        case .search: "Search"
        default: "Journal"
        }
        // From further up: the entries opened over this one go first, then this one.
        return [BackStep(title: title) {
            guard opened != nil else { dismiss(); return }
            opened = nil
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                dismiss()
            }
        }]
    }

    private var swipeForActions: some Gesture {
        // (Measured on the screen: the card it's on moves with the swipe.)
        DragGesture(minimumDistance: 30, coordinateSpace: .global)
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

    /// The bolt that slides in from the right edge as the entry is swiped (beside its card).
    @ViewBuilder
    private var swipeHint: some View {
        if swipeOffset < -4 {
            let progress = min(1, -swipeOffset / swipeThreshold)
            VStack(spacing: 6) {
                appIcon("slab-bolt")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(swipeArmed ? AnyShapeStyle(Color("OnAccent")) : AnyShapeStyle(.secondary))
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

    /// Swiping the title: the entry before this one by date (a swipe right, as if pulling it in
    /// from the left) or the one after (a swipe left), in place.
    private func step(to neighbour: EntryNeighbour?) async {
        guard let neighbour, !isStepping else { return }
        isStepping = true
        defer { isStepping = false }
        do {
            let other = try await model.entry(id: neighbour.id)
            playerHidden = true
            // On This Day is the entry's own: the one left behind's doesn't show under this one
            // while its own loads.
            sameDay = nil
            reading.headingPassed = false
            reading.passedMonths = []
            showsRelativeDate = false
            withAnimation(.easeInOut(duration: 0.2)) { entry = other }
        } catch is CancellationError {
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func jumpToADay(from entry: EntryDetail) {
        model.dayPickerOpensOn = entry.day
        model.showsDayPicker = true
    }

    /// The bar's title while On This Day is what's being read: its heading, as it is on the page.
    private var onThisDayTitle: some View {
        HStack(spacing: 8) {
            appIcon("slab-backward")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("On This Day")
                .font(.system(.headline, design: .serif, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .transition(.opacity)
    }

    /// Tap: the date or how long ago it was. Swipe: the entry before or after. Hold: Jump to a Day.
    private func dateTitle(for entry: EntryDetail) -> some View {
        let full = entry.day?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()) ?? entry.date
        let today = model.today?.day ?? JournalDay(localDate: .now)
        let relative = entry.day.map { $0.ago(from: today) } ?? full
        return Text(showsRelativeDate ? relative : full)
            .font(.headline)
            .foregroundStyle(.tint) // olive, like the dates over entries elsewhere
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .contentTransition(.opacity)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            // All the room between the bar's buttons, so there's something to swipe.
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .onTapGesture { toggleDate() }
            // Held: Jump to a Day's calendar, on this entry's month.
            .onLongPressGesture(minimumDuration: 0.45) {
                HoldHaptic.play()
                jumpToADay(from: entry)
            }
            .gesture(DragGesture(minimumDistance: 24).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                Task { await step(to: drag.translation.width > 0 ? entry.previousEntry : entry.nextEntry) }
            })
            .accessibilityElement()
            .accessibilityLabel(entry.day?.long ?? entry.date)
            .accessibilityValue(relative)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Switches between the date and how long ago it was. Swipe for the entry before or after.")
            .accessibilityAction { toggleDate() }
            .accessibilityAction(named: "Jump to a Day") { jumpToADay(from: entry) }
            .accessibilityAction(named: "Previous Entry") { Task { await step(to: entry.previousEntry) } }
            .accessibilityAction(named: "Next Entry") { Task { await step(to: entry.nextEntry) } }
            .animation(.easeOut(duration: 0.3), value: showsRelativeDate)
    }

    /// The entry before, Reflect and the entry after, in one group at the bottom's middle (over
    /// the song player when there is one): the obvious way to do what a pull down and a swipe on
    /// the date also do. Without Apple Intelligence it's just the two arrows; an arrow with
    /// nowhere to go is dimmed, so the group keeps its shape.
    private func floatingActions(for entry: EntryDetail) -> some View {
        HStack(spacing: 0) {
            floatingAction("slab-angle-left", "Previous Entry", isOn: entry.previousEntry != nil) { await step(to: entry.previousEntry) }
            if canReflect(entry) {
                floatingAction("slab-sparkles", "Reflect on This Entry") { await reflect(on: entry) }
            }
            floatingAction("slab-angle-right", "Next Entry", isOn: entry.nextEntry != nil) { await step(to: entry.nextEntry) }
        }
        .padding(.horizontal, 6)
        .modifier(GlassCapsule())
        .padding(.bottom, 10)
        .opacity(actionsHidden ? 0 : 1)
        .offset(y: actionsHidden ? 24 : 0)
        .allowsHitTesting(!actionsHidden)
        .accessibilityElement(children: .contain)
    }

    private func floatingAction(_ icon: String, _ name: String, isOn: Bool = true, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            appIcon(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isOn ? 1 : 0.3)
        .disabled(!isOn || isStepping)
        .accessibilityLabel(name)
    }

    private func toggleDate() {
        showsRelativeDate.toggle()
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

    /// Something to read over the photo: the writing, its dated tags or its songs.
    private var hasWriting: Bool {
        !entry.bodyText.isEmpty || entry.datedHashtags?.isEmpty == false || !entry.songs.isEmpty
    }

    private var hasPhoto: Bool { entry.imageProcessing || entry.imageURL != nil }
    /// The entry's last line is its writing: no dated tags or songs under it.
    private var endsInWriting: Bool { entry.datedHashtags?.isEmpty != false && entry.songs.isEmpty }

    // The writing is padded; the photo, after it, runs edge to edge and ends the entry.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasWriting {
                // (A little less above: the first line's own height adds to it. And under it,
                // before a photo, the gap Today's card has between an entry's words and its photo.
                // With no photo, as much room as On This Day's heading has above it, to the eye:
                // a last line of writing has its own height under the letters, which tags and
                // songs don't, so those get it added.)
                writing.padding(.horizontal).padding(.top, 12).padding(.bottom, hasPhoto ? 10 : (endsInWriting ? 28 : 32))
            }
            // Text first: Dabble Me is about the writing; photos follow it.
            if hasPhoto {
                EntryPhoto(url: entry.imageURL, isProcessing: entry.imageProcessing, day: entry.day, cornerRadius: 0)
                    .frame(maxWidth: .infinity)
            }
        }
        // An entry with nothing in it still takes a little room, not a line where it collapsed.
        .frame(minHeight: hasWriting || hasPhoto ? nil : 56)
    }

    private var writing: some View {
        // (The gap a Journal row has between an entry's words, its tags and its songs.)
        VStack(alignment: .leading, spacing: 10) {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// On This Day, under an entry: its calendar day in other years, earlier and later, each under
/// its month and year. Quieter than Today's rows (a few lines and a small photo), so a short
/// entry isn't drowned out by a long one from another year; a tap opens it. A free account sees
/// how many would be there (On This Day is PRO).
private struct SameDaySection: View {
    let entry: EntryDetail
    let sameDay: SameDayEntries
    /// How far down On This Day the page has been read (the bar follows it).
    let reading: ReadingSpot
    /// Today, by the journal's clock: how long ago each entry was is said from now, as
    /// everywhere else, not from the open entry.
    let today: JournalDay

    /// "November 2021 • 5 years ago".
    static func title(for entry: EntrySummary, today: JournalDay) -> String {
        guard let day = entry.day else { return entry.date }
        return "\(day.monthTitle) • \(day.ago(from: today))"
    }
    let onOpen: (Int) -> Void

    /// A month heading's height, in the page and in the bar.
    nonisolated static let headerHeight: CGFloat = 36

    // The page's lazy stack takes these as its own rows (no container around them).
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // (No rule of its own over it: the entry ends in a soft line just above.)
            HStack(spacing: 8) {
                // Light grey: a label's icon, as on Today.
                appIcon("slab-backward")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("On This Day")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            // Clear of the entry and the line it ends in.
            .padding(.top, 28)
            // Gone under the bar (the scroll view's space starts at the bar's foot).
            .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 0 } action: { passed in
                withAnimation(.easeOut(duration: 0.15)) { reading.headingPassed = passed }
            }
            if !sameDay.available {
                Text(sameDay.count == 1
                     ? "1 entry from another year would show here with Dabble Me PRO."
                     : "\(sameDay.count) entries from other years would show here with Dabble Me PRO.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
            }
        }
        .padding(.horizontal)
        if sameDay.available {
            ForEach(sameDay.entries) { other in
                MonthHeader(title: Self.title(for: other, today: today), isDay: true)
                    .padding(.horizontal)
                    .frame(height: Self.headerHeight)
                    .padding(.top, 8)
                    // At the top: the bar takes its month over. The scroll view's space starts at
                    // the bar's foot, and the bar's month line, once there is one, lies over the
                    // first of it: so the first heading hands over as it reaches the bar, and each
                    // one after as it reaches the line. One scrolled far enough away to be
                    // unloaded keeps what it last said.
                    .onGeometryChange(for: Bool.self) { [lineShown = !reading.passedMonths.isEmpty] proxy in
                        // (Part way under the line, so the same month isn't read twice at once.)
                        proxy.frame(in: .scrollView).minY <= (lineShown ? Self.headerHeight * 0.45 : 0)
                    } action: { passed in
                        if passed { reading.passedMonths.insert(other.id) } else { reading.passedMonths.remove(other.id) }
                    }
                MemoryRow(entry: other) { onOpen(other.id) }
                    // Held: the entry in the Journal's preview, with Open.
                    .modifier(MemoryPreview(entry: other) { onOpen(other.id) })
                    .padding(.horizontal)
                    .padding(.bottom, other.id == sameDay.entries.last?.id ? 24 : 4)
            }
        }
    }
}

/// One of On This Day's entries under an open entry: its date in the Journal's column, the start
/// of it (three lines) and its photo small beside it. The whole row opens the entry.
private struct MemoryRow: View {
    let entry: EntrySummary
    let open: () -> Void
    @ScaledMetric(relativeTo: .callout) private var textSize: CGFloat = 16
    @AppStorage(ReadingTextSize.storageKey) private var readingSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif

    /// The entry's words, without the dated tags and song links at their end (as a Journal row
    /// leaves them off); an entry that's only a photo or a song says so.
    private var preview: String {
        let songs = entry.songs ?? []
        let text = RichText.droppingTrailing(hashtags: (entry.datedHashtags ?? []).map(\.tag), songLinks: !songs.isEmpty, from: entry.excerpt)
            .replacingOccurrences(of: #"https?://open\.spotify\.com/\S+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        if entry.imageURL != nil || entry.imageProcessing { return "📷 Photo" }
        return songs.first.map { "🎶 \($0.label)" } ?? entry.excerpt
    }

    var body: some View {
        // A tap, not a Button: a button would also open the entry at the end of a sideways swipe
        // that began and ended on it.
        row
            .contentShape(.rect)
            .onTapGesture(perform: open)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.day?.long ?? entry.date). \(preview)")
            .accessibilityHint("Opens the entry")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(entry.day?.weekdayShort.uppercased() ?? "")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.day?.dayNumber ?? "")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 42)
            Text(preview)
                .font(.system(size: textSize * readingSize.scale, design: fontStyle.design))
                .foregroundStyle(.primary.opacity(0.82))
                .lineSpacing(3)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let url = entry.thumbnailURL(width: 300, height: 300) {
                EntryThumbnail(url: url)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Where an open entry is scrolled to: how far down, how much of it shows, and how long it is.
private struct ScrollSpot: Equatable {
    var offset: CGFloat
    var viewport: CGFloat
    var content: CGFloat
}

/// The tab bar's glass for a floating group of buttons (a material before iOS 26).
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.regularMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(.quaternary))
        }
    }
}

/// Touch and hold an On This Day row: that entry's preview, as a day's in Stats.
private struct MemoryPreview: ViewModifier {
    let entry: EntrySummary
    let open: () -> Void
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if let day = entry.day {
            content.dayPreview(day, isWritten: true, summary: entry, model: model, open: open, write: nil)
        } else {
            content
        }
    }
}

/// A strip under the navigation bar that reads as part of it: iOS 26 runs the bar's own
/// see-through backing on under it (`safeAreaBar`); before that it has the bar material.
private struct TopBarExtension<Strip: View>: ViewModifier {
    /// Nothing, until there's something to show.
    @ViewBuilder var strip: Strip

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.safeAreaBar(edge: .top, spacing: 0) { strip }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) { strip }
        }
    }
}

/// How far down On This Day an open entry has been read. Kept apart from the entry's page, so
/// that scrolling past a heading redraws only the two things that follow it (the bar's title and
/// its month line) and not the whole page, which made the hand-over stutter.
@MainActor @Observable
final class ReadingSpot {
    /// On This Day's heading has scrolled up under the bar (which then says so in the date's place).
    var headingPassed = false
    /// The entries whose month headings have scrolled up past the top (the bar shows the last's).
    var passedMonths: Set<Int> = []
}

/// The bar's title: the entry's date, or "On This Day" once that's what's being read.
private struct EntryTitle<OnThisDay: View, DateTitle: View>: View {
    let reading: ReadingSpot
    let hasOnThisDay: Bool
    @ViewBuilder var onThisDay: OnThisDay
    @ViewBuilder var date: DateTitle

    var body: some View {
        if reading.headingPassed, hasOnThisDay { onThisDay } else { date }
    }
}

/// The month of the On This Day entry being read, as a line under the bar.
private struct PinnedMonth: View {
    let reading: ReadingSpot
    let entries: [EntrySummary]
    let today: JournalDay

    var body: some View {
        if reading.headingPassed, let current = entries.last(where: { reading.passedMonths.contains($0.id) }) {
            MonthHeader(title: SameDaySection.title(for: current, today: today), isDay: true)
                .padding(.horizontal)
                .frame(height: SameDaySection.headerHeight)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .modifier(BarBackingBefore26())
        }
    }
}

/// Before iOS 26 a strip under the bar needs the bar's material itself.
private struct BarBackingBefore26: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content } else { content.background(.bar) }
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
        case offer, working, preview([JournalIntelligence.ChatSummary]), saving([JournalIntelligence.ChatSummary]), added, failed(String), dismissed
    }
    /// Reads the reflection aloud (the phone's own voice, on the device).
    /// After the reflection, a chat about the entry (on the device, never saved).
    @State private var chat: ReflectionChat?
    @State private var draft = ""
    /// Counts the replies sent: each gets a field of its own.
    @State private var field = 0
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
                                TypingDots(size: .large)
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
                .id(field) // a new one after each send (see `send`)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 20))
                .accessibilityIdentifier("ReflectionReply")
                .onSubmit(send)
            Button(action: send) {
                appIcon("slab-arrow-up")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color("OnAccent"))
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
                Text("If you'd like to keep this, I can add the question and your answer, tidied up, to this day's entry.")
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
                    TypingDots(size: .small)
                    Text("Summing up…").foregroundStyle(.secondary)
                }
            case .preview(let text), .saving(let text):
                // As it'll read in the entry: each question in bold, its answer under it.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(text.enumerated()), id: \.offset) { _, part in
                        Text(part.question.isEmpty ? "" : part.question + "\n").bold() + Text(part.answer)
                    }
                }
                    // (Read as one piece, as it'll be in the entry.)
                    .accessibilityElement(children: .combine)
                    .font(.system(.body, design: .serif))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.tint.opacity(0.08), in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("ReflectionSummary")
                HStack(spacing: 10) {
                    Button("Add to Entry") { Task { await addToEntry(text) } }
                        .filledButtonStyle()
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
            let text = try await JournalIntelligence.chatSummary(entry: reflection.entryText, reflection: reflection.text ?? "",
                                                                 conversation: chat.messages)
            summary = .preview(text)
        } catch {
            summary = .failed(error.localizedDescription)
        }
    }

    /// Adds the questions and their answers at the end of the entry, through the usual edit: each
    /// question as a bold paragraph and its answer under it, as a prompt answered while writing is.
    private func addToEntry(_ text: [JournalIntelligence.ChatSummary]) async {
        guard let id = reflection.entryID, let document = reflection.document else { return }
        summary = .saving(text)
        do {
            var added: [DocumentBlock] = []
            for part in text {
                if !part.question.isEmpty { added.append(.paragraph(DocumentRun(part.question, bold: true))) }
                added.append(.paragraph(DocumentRun(part.answer)))
            }
            let updated = try await model.updateEntry(id: id, document: document + added)
            onEntryUpdated(updated)
            summary = .added
        } catch {
            summary = .failed(error.localizedDescription)
        }
    }

    private func send() {
        guard let text = reflection.text else { return }
        let message = draft
        let wasTyping = replying
        draft = ""
        // A fresh field for the next reply. The keyboard can put the sent words back in the old
        // one (a pending autocorrection or dictation, committed as Send is tapped), or leave them
        // showing though the draft is empty; a new field has none of that to bring back.
        field += 1
        Task { @MainActor in
            if wasTyping { replying = true } // the keyboard stays up, on the new field
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
            // The reply being written: the app's typing dots, where its words will be.
            TypingDots()
                .accessibilityLabel("Writing a reply")
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

/// Hashtags with a date (like the web's "Tags:"), on one line that scrolls sideways: each pill
/// shows how long it had been on this entry's day, briefly ("3yrs, 5mos"). Tap to search;
/// long-press for the tag's date, with the age in full.
struct DatedHashtagRow: View {
    let hashtags: [DatedHashtag]
    @Environment(\.openURL) private var openURL
    /// All of them, wrapped, after a tap on "+2".
    @State private var showsAll = false

    var body: some View {
        // One line: as many as fit, then "+2" for the rest, which wraps them all down the page.
        // (Not a line that scrolls sideways: rows and the open entry have swipes of their own.)
        if showsAll || hashtags.count < 2 {
            FlowLayout(spacing: 6) { pills(hashtags.count) }
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach((1...hashtags.count).reversed(), id: \.self) { count in
                    HStack(spacing: 6) { pills(count) }
                }
            }
        }
    }

    @ViewBuilder
    private func pills(_ count: Int) -> some View {
        pillButtons(hashtags.prefix(count))
        if count < hashtags.count {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showsAll = true }
            } label: {
                Text("+\(hashtags.count - count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.12), in: .rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(hashtags.count - count) more dated tags")
        }
    }

    private func pillButtons(_ shown: ArraySlice<DatedHashtag>) -> some View {
        Group {
            ForEach(shown) { hashtag in
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
/// dated tag ("#Leo  3yrs, 4mos"), on one line. Under entries, in the Actions sheet, and
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
        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 8))
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
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
    }

    /// The age as the pill has room for it: "7 years, 11 months" (or "… and 11 months since
    /// entry", from an older server) → "7yrs, 11mos"; a tag dated after the entry, "3 months from
    /// entry" → "In 3mos"; "today" → "Today".
    static func shortAge(_ age: String) -> String {
        var short = age.replacingOccurrences(of: " since entry", with: "").replacingOccurrences(of: " and ", with: ", ")
        if short.hasSuffix(" from entry") { short = "in " + short.dropLast(" from entry".count) }
        for (unit, abbreviation) in [("years", "yrs"), ("year", "yr"), ("months", "mos"), ("month", "mo"),
                                     ("weeks", "wks"), ("week", "wk"), ("days", "days"), ("day", "day")] {
            short = short.replacingOccurrences(of: "(\\d+) \(unit)\\b", with: "$1\(abbreviation)", options: .regularExpression)
        }
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
