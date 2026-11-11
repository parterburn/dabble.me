import SwiftUI

struct EntryRoute: Hashable {
    let id: Int
}

/// The Journal tab's views, picked from the menu on its title.
enum JournalMode: String, CaseIterable, Identifiable {
    case list = "Journal"
    case stats = "Stats"
    case photos = "Photos"

    var id: Self { self }

    var icon: String {
        switch self {
        case .list: "slab-list"
        case .stats: "slab-signal-bars"
        case .photos: "slab-images"
        }
    }
}

struct JournalView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("journal.mode") private var mode = JournalMode.list
    @State private var path = NavigationPath()
    @State private var expanded: Set<Int> = []
    /// The title bar hides while scrolling down; `barAnchor` is where the current direction began.
    @State private var barHidden = false
    @State private var barAnchor: CGFloat = 0
    @State private var barChanged = Date.distantPast
    @State private var isDragging = false
    @State private var handledStatsRequest = 0
    /// Bumped to scroll the timeline to its newest entry (after the List view is back on screen).
    @State private var scrollToTop = 0
    /// Tapping the timeline scrubber: a calendar of written days, and the day picked from it.
    @State private var actions = EntryActions()
    @State private var composing = false
    @State private var showingProInfo = false
    @State private var scrollProgress: CGFloat = 0
    @State private var isScrolling = false

    var body: some View {
        NavigationStack(path: $path) {
            modeContent
                .navigationTitle(mode.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarTitleMenu {
                    Picker("View", selection: $mode) {
                        ForEach(JournalMode.allCases) { mode in
                            Label(mode.rawValue, icon: mode.icon).tag(mode)
                        }
                    }
                }
                .navigationDestination(for: EntryRoute.self) { EntryDetailView(entryID: $0.id) }
                .toolbar {
                    // The "me" mark, always in view.
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .topBarLeading) { brandMark }
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .topBarLeading) { brandMark }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { startWriting() } label: { Label("New Entry", icon: "slab-plus") }
                    }
                }
                .sheet(isPresented: $composing) { ComposeView(mode: .new) }
                .entryActionSheets(actions)
                // "Open" from the shake-for-a-memory sheet, or the widget's entry. Also on first
                // appearing: the Journal tab may not exist yet when the request comes.
                .onChange(of: model.openEntryRequest, initial: true) { _, id in
                    guard let id else { return }
                    model.openEntryRequest = nil
                    mode = .list
                    path.append(EntryRoute(id: id))
                }
                // Also on first appearing: the Journal tab may not exist yet when Today asks.
                .onChange(of: model.statsRequest, initial: true) { _, request in
                    guard request != handledStatsRequest else { return }
                    handledStatsRequest = request
                    path = NavigationPath()
                    mode = .stats
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

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .list: content
        case .stats:
            if model.me?.maySeeStats == false {
                ProInfoView(feature: .stats, showsDoneButton: false)
            } else {
                StatsView()
            }
        case .photos: PhotoGridView { path.append($0) }
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
                    Text("Reply to your Dabble Me email and your entry will show up here.")
                } actions: {
                    if model.me?.canWrite == true {
                        Button("Write Your First Entry") { composing = true }
                    }
                }
                .refreshable { await model.refresh() }
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
            .refreshable {
                withAnimation(.snappy(duration: 0.25)) { expanded = [] }
                await model.refresh()
            }
            .onChange(of: scrollToTop) {
                guard let month = model.months.first else { return }
                withAnimation {
                    if let first = model.monthEntries[month.key]?.first {
                        proxy.scrollTo(first.id, anchor: .top)
                    } else {
                        proxy.scrollTo(PlaceholderID(month: month.key, index: 0), anchor: .top)
                    }
                }
            }
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
                    TimelineScrubber(months: model.months, progress: scrollProgress, isScrolling: isScrolling, onSelect: { month in
                        // Jump to the month's first row: its first entry if loaded, else its first placeholder.
                        if let first = model.monthEntries[month.key]?.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        } else {
                            proxy.scrollTo(PlaceholderID(month: month.key, index: 0), anchor: .top)
                        }
                    }, onRelease: { month in
                        // Load where the scrubber landed now, rather than waiting for rows to settle.
                        Task { await model.loadMonths(around: month.key) }
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

    /// A month's rows under its sticky "Month YYYY" header (an expanded entry's date floats down
    /// its left side, so the header stays the month).
    @ViewBuilder
    private func monthSections(_ month: MonthCount) -> some View {
        if let entries = model.monthEntries[month.key] {
            Section {
                ForEach(entries) { entry in
                    TimelineEntryRow(entry: entry, isExpanded: expanded.contains(entry.id), actions: actions,
                                     onExpand: { expand(entry) }, onOpen: { path.append(EntryRoute(id: entry.id)) })
                        .entryRowMenu(entry, actions: actions) { path.append(EntryRoute(id: entry.id)) }
                        .timelineRowLayout()
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

    private func expand(_ entry: EntrySummary) {
        withAnimation(.snappy(duration: 0.25)) { _ = expanded.insert(entry.id) }
    }

    private var brandMark: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: 44, height: 44) // the size of the + button opposite
            .clipShape(.circle)
            .accessibilityHidden(true)
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
