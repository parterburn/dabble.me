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
    @State private var scrubberLabel: String?
    /// Bumped to scroll the timeline to its newest entry (after the List view is back on screen).
    @State private var scrollToTop = 0
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
                    ToolbarItem(placement: .primaryAction) {
                        Button { startWriting() } label: { Label("New Entry", icon: "slab-plus") }
                    }
                }
                .sheet(isPresented: $composing) { ComposeView(mode: .new) }
                .entryActionSheets(actions)
                .onChange(of: model.openEntryRequest) { _, id in
                    // "Open" from the shake-for-a-memory sheet.
                    guard let id else { return }
                    model.openEntryRequest = nil
                    mode = .list
                    path.append(EntryRoute(id: id))
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
            }
            .overlay(alignment: .trailing) {
                if model.months.count >= 3 {
                    TimelineScrubber(months: model.months, progress: scrollProgress, isScrolling: isScrolling,
                                     visibleMonth: model.topVisibleMonth, onSelect: { month in
                        // Jump to the month's first row: its first entry if loaded, else its first placeholder.
                        if let first = model.monthEntries[month.key]?.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        } else {
                            proxy.scrollTo(PlaceholderID(month: month.key, index: 0), anchor: .top)
                        }
                    }, onRelease: { month in
                        // Load where the scrubber landed now, rather than waiting for rows to settle.
                        Task { await model.loadMonths(around: month.key) }
                    }, label: $scrubberLabel)
                }
            }
            // Google Photos' month pill: which month you're in while the scrubber shows.
            .overlay(alignment: .top) {
                if let scrubberLabel {
                    Text(scrubberLabel)
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: .capsule)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                        .padding(.top, 44) // below the sticky month header
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.2), value: scrubberLabel == nil)
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

    private func expand(_ entry: EntrySummary) {
        withAnimation(.snappy(duration: 0.25)) { _ = expanded.insert(entry.id) }
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
    /// An expanded entry's date (pinned while reading it), a little stronger than a month.
    var isDay = false

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary.opacity(isDay ? 0.85 : 0.7))
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
