import SwiftUI

struct EntryRoute: Hashable {
    let id: Int
}

/// The Journal tab's views, picked from the menu on its title, in the menu's order: Stats is
/// the one looked at least, so it's last.
enum JournalMode: String, CaseIterable, Identifiable {
    case list = "Journal"
    case photos = "Photos"
    case playlist = "Songs"
    case stats = "Stats"

    var id: Self { self }

    var icon: String {
        switch self {
        case .list: "slab-list"
        case .stats: "slab-chart-bar"
        case .photos: "slab-images"
        case .playlist: "slab-music"
        }
    }
}

struct JournalView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("journal.mode") private var mode = JournalMode.list
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path = NavigationPath()
    /// On a wide screen, the entry open beside the timeline (see `EntryPaneLayout`).
    @State private var routing = EntryPaneRouting()
    @State private var expanded: Set<Int> = []
    /// The title bar hides while scrolling down; `barAnchor` is where the current direction began.
    @State private var barHidden = false
    @State private var barAnchor: CGFloat = 0
    @State private var barChanged = Date.distantPast
    @State private var isDragging = false
    @State private var handledStatsRequest = 0
    /// The list of the Journal's views is open under the title.
    @State private var choosingMode = false
    /// Where the list's rows are on screen, and the one the finger is over when it's dragged down
    /// from the title without lifting.
    @State private var modeFrames: [JournalMode: CGRect] = [:]
    @State private var draggedOver: JournalMode?
    @State private var pulledOpenAt = Date.distantPast
    /// The "me" mark was held (for Jump to a Day): the tap that ends the hold isn't one.
    @State private var heldMark = false
    /// A jump to a far month that's still being brought home (`settle`).
    @State private var jump: Task<Void, Never>?
    /// Bumped to scroll the timeline to its newest entry (after the List view is back on screen).
    @State private var scrollToTop = 0
    /// Tapping the timeline scrubber: a calendar of written days, and the day picked from it.
    @State private var actions = EntryActions()
    @State private var composing = false
    @State private var showingProInfo = false
    @State private var scrollProgress: CGFloat = 0
    @State private var isScrolling = false

    /// Entries open beside the list: a wide screen, and a view that opens entries (Stats doesn't).
    private var showsPane: Bool { sizeClass == .regular && mode != .stats }

    var body: some View {
        EntryPaneLayout(showsPane: showsPane, entry: $routing.paneEntry) { stack }
            .animation(.snappy(duration: 0.25), value: showsPane)
            .onChange(of: path.count) { _, count in routing.pathChanged(count: count) }
            // Opened or closed (iPhone Duo), or an iPad's window resized: the open entry moves
            // between the pane and the stack. Not while on Stats, whose pane is just hidden.
            .onChange(of: sizeClass) {
                guard mode != .stats else { return }
                routing.widthChanged(wide: showsPane, path: &path)
            }
    }

    /// Opens an entry: beside the list on a wide screen, over it otherwise.
    private func open(_ route: EntryRoute) {
        routing.open(route, wide: showsPane, path: &path)
    }

    private var stack: some View {
        NavigationStack(path: $path) {
            modeContent
                .navigationTitle(mode.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: EntryRoute.self) { EntryDetailView(entryID: $0.id) }
                .toolbar {
                    // The "me" mark, always in view.
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .topBarLeading) { brandMark }
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .topBarLeading) { brandMark }
                    }
                    // The title opens the Journal's views: a size up from a plain title, with a
                    // chevron in the tint, so it reads as something to open. A tap opens them, and so
                    // does pulling down on it: keep the finger down and carry on to a view, and letting
                    // go there picks it, as a system menu would. (The app's own list, not a system
                    // menu: that can't show the view that's on in olive.)
                    ToolbarItem(placement: .principal) {
                        Button { choosingMode = true } label: {
                            HStack(spacing: 7) {
                                Text(mode.rawValue)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                // Large enough to say the title opens something.
                                appIcon("slab-angle-down")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(.tint)
                            }
                            .frame(minWidth: 190, minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(DragGesture(minimumDistance: 12, coordinateSpace: .global)
                            .onChanged { drag in
                                // Pulled down: the list opens under the finger, which is then over
                                // one of its rows or none.
                                if !choosingMode, drag.translation.height > 16, abs(drag.translation.width) < 60 {
                                    choosingMode = true
                                    pulledOpenAt = .now
                                }
                                guard choosingMode else { return }
                                let over = modeFrames.first { $0.value.contains(drag.location) }?.key
                                if over != draggedOver { draggedOver = over }
                            }
                            .onEnded { _ in
                                // Let go over a view: that's the one. Let go elsewhere, and the list
                                // stays open; so it does after a quick pull that's over before the
                                // list is there to choose from (its first row lands under the finger).
                                defer { draggedOver = nil }
                                guard let picked = draggedOver, Date.now.timeIntervalSince(pulledOpenAt) > 0.35 else { return }
                                choosingMode = false
                                mode = picked
                            })
                        .sensoryFeedback(.selection, trigger: draggedOver) { _, over in over != nil }
                        .popover(isPresented: $choosingMode, arrowEdge: .top) { modeList }
                        .accessibilityLabel(mode.rawValue)
                        .accessibilityHint("Chooses another view of your journal")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { startWriting() } label: { Label("New Entry", icon: "slab-plus") }
                    }
                }
                // Once written, the new entry opens in full under the closing composer.
                .sheet(isPresented: $composing) { ComposeView(mode: .new) { open(EntryRoute(id: $0.id)) } }
                .entryActionSheets(actions) { open(EntryRoute(id: $0)) }
                // "Open" from the shake-for-a-memory sheet, or the widget's entry. Also on first
                // appearing: the Journal tab may not exist yet when the request comes.
                .onChange(of: model.openEntryRequest, initial: true) { _, id in
                    guard let id else { return }
                    model.openEntryRequest = nil
                    mode = model.openEntryOver ?? .list
                    model.openEntryOver = nil
                    open(EntryRoute(id: id))
                }
                // Also on first appearing: the Journal tab may not exist yet when Today asks.
                .onChange(of: model.statsRequest, initial: true) { _, request in
                    guard request != handledStatsRequest else { return }
                    handledStatsRequest = request
                    path = NavigationPath()
                    mode = .stats
                }
                .onChange(of: model.journalModeRequest, initial: true) { _, request in
                    guard let request else { return }
                    model.journalModeRequest = nil
                    path = NavigationPath()
                    mode = request
                }
                .onChange(of: model.journalTopRequest) {
                    path = NavigationPath()
                    mode = .list
                    Task {
                        try? await Task.sleep(for: .milliseconds(80))
                        scrollToTop += 1
                    }
                }
                .sheet(isPresented: $showingProInfo) { ProInfoView(feature: .writing) }
        }
    }

    /// The Journal's views, in a popover under the title: the one showing in olive, with its
    /// filled icon.
    private var modeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(JournalMode.allCases) { option in
                let isOn = option == mode
                Button {
                    choosingMode = false
                    mode = option
                } label: {
                    HStack(spacing: 14) {
                        appIcon(isOn ? option.icon + "-full" : option.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text(option.rawValue)
                            .font(.body.weight(isOn ? .semibold : .regular))
                        Spacer(minLength: 24)
                    }
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 20)
                    .frame(height: 50)
                    .contentShape(.rect)
                    // Under a finger dragged down from the title.
                    .background(draggedOver == option ? Color.primary.opacity(0.08) : .clear)
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { modeFrames[option] = $0 }
                .accessibilityIdentifier("JournalMode-\(option.rawValue)")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .frame(minWidth: 210)
        .onDisappear { modeFrames = [:]; draggedOver = nil }
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .list: content
        case .stats:
            if model.me?.maySeeStats == false {
                ProInfoView(feature: .stats, showsDoneButton: false,
                            rewindYear: RewindSeason.year(on: model.today?.day ?? JournalDay(localDate: .now)))
            } else {
                // Its Entries and Photos tiles go to those views.
                StatsView { mode = $0 }
            }
        case .photos: PhotoGridView { open($0) }
        case .playlist: PlaylistView { open($0) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.months.isEmpty {
            if !model.hasLoaded && model.timelineError == nil {
                ProgressView()
            } else if let error = model.timelineError {
                ContentUnavailableView {
                    Label("Couldn't load your journal", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            } else {
                ContentUnavailableView {
                    Label("No entries yet", icon: "slab-envelope")
                } description: {
                    // Only for someone who can't write in the app: otherwise the button is the way in.
                    if model.me?.canWrite != true {
                        Text("Reply to your Dabble Me email and your entry will show up here.")
                    }
                } actions: {
                    if model.me?.canWrite == true {
                        Button("Write Your First Entry") { composing = true }
                            .filledButtonStyle()
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .fontWeight(.medium)
                            .padding(.top, 21) // as far under the title as the icon is over it
                    }
                }
                .refreshDots { await model.refresh() }
            }
        } else {
            timeline
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            List {
                if let error = model.timelineError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.months) { month in
                    monthSections(month)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden) // the timeline scrubber replaces the standard indicator
            .timelinePinsDates()
            // Pull to reset: collapses expanded entries and picks up new ones.
            .refreshDots {
                withAnimation(.snappy(duration: 0.25)) { expanded = [] }
                await model.refresh()
            }
            .onChange(of: scrollToTop) {
                jump?.cancel()
                guard let month = model.months.first else { return }
                withAnimation {
                    if let first = model.monthEntries[month.key]?.first {
                        proxy.scrollTo(first.id, anchor: .top)
                    } else {
                        proxy.scrollTo(PlaceholderID(month: month.key, index: 0), anchor: .top)
                    }
                }
            }
            // A finger on the list takes over from a jump that's still settling.
            .onChange(of: isDragging) { _, dragging in if dragging { jump?.cancel() } }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let scrollable = geometry.contentSize.height - geometry.containerSize.height
                return scrollable > 0 ? min(max((geometry.contentOffset.y + geometry.contentInsets.top) / scrollable, 0), 1) : 0
            } action: { _, progress in
                scrollProgress = progress
            }
            .onScrollPhaseChange { _, phase in
                isScrolling = phase.isScrolling
                isDragging = phase == .interacting || phase == .decelerating
            }
            .overlay(alignment: .trailing) {
                if model.months.count >= 3 {
                    // Beside the entry pane, held in from the list's edge: on iPhone Duo that
                    // edge is the fold, where a thumb is hard to grab.
                    TimelineScrubber(months: model.months, progress: scrollProgress, isScrolling: isScrolling, inset: showsPane ? TimelineScrubber.foldInset : 0, onSelect: { month in
                        jump?.cancel()
                        // Jump to the month's first row: its first entry if loaded, else its first placeholder.
                        if let first = model.monthEntries[month.key]?.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        } else {
                            proxy.scrollTo(PlaceholderID(month: month.key, index: 0), anchor: .top)
                        }
                    }, onRelease: { month in
                        // Load where the scrubber landed now, and make sure the list really is
                        // there: a far jump lands short (below).
                        jump?.cancel()
                        jump = Task { await settle(proxy, on: month) }
                    }, onTap: {
                        model.showsDayPicker = true
                    })
                }
            }
            // Only the month header stays while reading down; the title bar comes back on the
            // way up (or at the top).
            // The content offset alone: the bar showing or hiding changes the top inset, which
            // mustn't read as scrolling (that would flip it back and forth). With the content's
            // height, so a jump from rows loading or resizing isn't taken for scrolling either.
            .onScrollGeometryChange(for: BarScroll.self) { BarScroll(offset: $0.contentOffset.y, height: $0.contentSize.height) } action: { old, new in
                updateBar(for: new.offset, contentResized: abs(new.height - old.height) > 1)
            }
            .toolbarVisibility(barHidden ? .hidden : .visible, for: .navigationBar)
            .animation(.easeInOut(duration: 0.2), value: barHidden)
        }
    }

    /// Makes a far jump arrive. The list only guesses the heights of rows it hasn't drawn, and
    /// real rows (photos, long entries) are taller than its guess, so one jump across years of
    /// them stops short. This loads the month, then jumps again and again, each from nearer with
    /// more rows measured, until the month is on screen and stays there.
    @MainActor
    private func settle(_ proxy: ScrollViewProxy, on month: MonthCount) async {
        func go() {
            if let first = model.monthEntries[month.key]?.first {
                proxy.scrollTo(first.id, anchor: .top)
            } else {
                proxy.scrollTo(PlaceholderID(month: month.key, index: 0), anchor: .top)
            }
        }
        withAnimation { go() }
        await model.loadMonths(around: month.key)
        // Arrived once the month has its entries and has stayed put for a few looks. (It may
        // have been loading already, in which case the wait above was no wait at all.)
        var arrived = 0
        for _ in 0..<40 {
            guard !Task.isCancelled else { return }
            go()
            try? await Task.sleep(for: .milliseconds(200))
            arrived = model.monthEntries[month.key] != nil && model.isMonthVisible(month.key) ? arrived + 1 : 0
            if arrived >= 3 { break }
        }
        guard !Task.isCancelled else { return }
        go()
    }

    /// A month's rows under its sticky "Month YYYY" header (an expanded entry's date floats down
    /// its left side, so the header stays the month).
    @ViewBuilder
    private func monthSections(_ month: MonthCount) -> some View {
        if let entries = model.monthEntries[month.key] {
            Section {
                ForEach(entries) { entry in
                    TimelineEntryRow(entry: entry, isExpanded: expanded.contains(entry.id), actions: actions,
                                     onExpand: { if showsPane { open(EntryRoute(id: entry.id)) } else { expand(entry) } }, onOpen: { open(EntryRoute(id: entry.id)) })
                        .entryRowMenu(entry, actions: actions) { open(EntryRoute(id: entry.id)) }
                        .timelineRowLayout()
                        .listRowBackground(openRowBackground(entry.id))
                }
            } header: {
                MonthHeader(title: month.title)
                    .onAppear { model.monthAppeared(month.key) }
                    .onDisappear { model.monthDisappeared(month.key) }
            }
            .task {
                // Reload a month a refresh marked stale once it's back on screen.
                guard model.isStale(month.key) else { return }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await model.loadMonth(month.key)
            }
        } else {
            Section {
                // Placeholders sized like real rows keep scrolling (and the scrubber) proportional.
                ForEach(0..<month.count, id: \.self) { index in
                    EntryRowPlaceholder()
                        .id(PlaceholderID(month: month.key, index: index))
                        .timelineRowLayout()
                }
                .task {
                    // Wait until the month settles on screen, so flicking or scrubbing past it
                    // doesn't fire a request for every month along the way.
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    await model.loadMonth(month.key)
                }
            } header: {
                MonthHeader(title: month.title)
                    .onAppear { model.monthAppeared(month.key) }
                    .onDisappear { model.monthDisappeared(month.key) }
            }
        }
    }

    /// Hides the bar after ~40pt of scrolling down and shows it after ~60pt up, only while the
    /// person is scrolling, and not again for a moment after it changes.
    private struct BarScroll: Equatable {
        let offset: CGFloat
        let height: CGFloat
    }

    private func updateBar(for offset: CGFloat, contentResized: Bool = false) {
        // Rows loading (placeholders turning into entries) move the offset without anyone scrolling.
        guard !contentResized, Date.now.timeIntervalSince(barChanged) > 0.35 else { barAnchor = offset; return }
        let wasHidden = barHidden
        defer { if barHidden != wasHidden { barChanged = .now } }
        if offset < 0 {
            barHidden = false
            barAnchor = offset
        } else if !isDragging {
            barAnchor = offset
        } else if barHidden {
            if offset > barAnchor { barAnchor = offset } else if barAnchor - offset > 60 { barHidden = false; barAnchor = offset }
        } else {
            if offset < barAnchor { barAnchor = offset } else if offset - barAnchor > 40 { barHidden = true; barAnchor = offset }
        }
    }

    /// The row of the entry open in the pane, tinted so it's clear which one that is.
    private func openRowBackground(_ id: Int) -> Color? {
        showsPane && routing.paneEntry?.id == id ? Color.accentColor.opacity(0.1) : nil
    }

    private func expand(_ entry: EntrySummary) {
        withAnimation(.snappy(duration: 0.25)) { _ = expanded.insert(entry.id) }
    }

    private var brandMark: some View {
        // A tap is the way back to the list from Stats, Photos or the Playlist, and on the list
        // it's back to the top; held, it's Jump to a Day's calendar.
        Button {
            // Not the tap that ends a hold.
            if heldMark { heldMark = false } else if mode != .list { mode = .list } else { scrollToTop += 1 }
        } label: {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44) // the size of the + button opposite
                .clipShape(.circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            heldMark = true
            HoldHaptic.play()
            model.showsDayPicker = true
        })
        .onChange(of: model.showsDayPicker) { _, open in if !open { heldMark = false } }
        .accessibilityIdentifier("JournalBrandMark")
        .accessibilityLabel("Dabble Me")
        .accessibilityHint(mode == .list ? "Scrolls to the top. Touch and hold to jump to a day." : "Shows your journal as a list")
        .accessibilityAction(named: "Jump to a Day") { model.showsDayPicker = true }
    }

    private func startWriting() {
        if model.me?.canWrite == true {
            composing = true
        } else {
            showingProInfo = true
        }
    }

}

private struct PlaceholderID: Hashable {
    let month: String
    let index: Int
}

struct MonthHeader: View {
    let title: String
    /// A day's date rather than a month (On This Day, a throwback).
    var isDay = false

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.tint) // olive, like Random Memory's date
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct EntryRowPlaceholder: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 42, height: 40)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 14)
                }
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 180, height: 14)
            }
        }
        .padding(.vertical, 4)
        .frame(height: 150, alignment: .top) // about a real row with a few lines (some have photos)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

extension Binding where Value == Bool {
    /// `true` while `optional` is non-nil; setting `false` clears it. For alerts driven by an error message.
    static func present<T: Sendable>(_ optional: Binding<T?>) -> Binding<Bool> {
        Binding(get: { optional.wrappedValue != nil }, set: { if !$0 { optional.wrappedValue = nil } })
    }
}
