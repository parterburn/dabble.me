import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    /// The last "focus the search field" request handled (tapping Search again, or a quick action).
    @State private var handledFocusRequest = 0
    @State private var submitted = ""
    @State private var results: [EntrySummary] = []
    @State private var nextPage: Int?
    @State private var totalCount = 0
    @State private var isSearching = false
    @State private var error: String?
    @State private var hashtags: [HashtagCount] = []
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool
    @State private var path = NavigationPath()
    @State private var expanded: Set<Int> = []
    @State private var actions = EntryActions()
    /// For the timeline scrubber over the results (as on the Journal).
    @State private var scrollProgress: CGFloat = 0
    @State private var isScrolling = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.me?.canSearch == false {
                    ProInfoView(feature: .search, showsDoneButton: false)
                } else {
                    resultsList
                        // Swiping down (or scrolling the results) hides the keyboard, even on the
                        // screens that don't scroll (no results yet, nothing found).
                        .scrollDismissesKeyboard(.immediately)
                        .contentShape(.rect)
                        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                            if value.translation.height > 40 { isSearchFocused = false }
                        })
                        // Always visible at the top, not tucked away when the results scroll.
                        .searchable(text: $query, isPresented: $isSearchActive,
                                    placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your journal")
                        .searchFocused($isSearchFocused)
                        // With results showing, search is already "active", so focus the field itself.
                        // Also on first appearing: a quick action can ask before Search exists.
                        .onChange(of: model.searchFocusRequest, initial: true) { _, request in
                            guard request > handledFocusRequest else { return }
                            handledFocusRequest = request
                            isSearchActive = true
                            isSearchFocused = true
                        }
                        .onSubmit(of: .search) { Task { await search(reset: true) } }
                        .onChange(of: query) { _, newValue in
                            if newValue.isEmpty { clear() }
                        }
                        .onChange(of: model.searchRequest, initial: true) { _, request in
                            guard let request else { return }
                            model.searchRequest = nil
                            path = NavigationPath() // e.g. a #hashtag tapped in an entry opened from these results
                            query = request
                            Task { await search(reset: true) }
                        }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title) // the tab says where you are
            .navigationDestination(for: EntryRoute.self) { EntryDetailView(entryID: $0.id) }
            .entryActionSheets(actions)
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if submitted.isEmpty {
            // Before a search: how to search, your hashtags, a way to a day, and where to ask more.
            // (No pull to refresh here: the hashtags reload each time Search comes up.)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Search for a word, a #hashtag, an \"exact phrase\", or either of two words with hiking OR camping.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !hashtags.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Your Hashtags This Year")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            HashtagCloud(hashtags: hashtags) { tag in
                                query = "#\(tag)"
                                Task { await search(reset: true) }
                            }
                        }
                    }
                    VStack(spacing: 12) {
                        Button {
                            model.showsDayPicker = true
                        } label: {
                            SearchRow(icon: "slab-calendar", title: "Jump to a Day", message: "See your entries in a calendar view.")
                        }
                        .accessibilityLabel("Jump to a Day")
                        .accessibilityHint("Opens a calendar of the days you wrote")
                        // The Claude/ChatGPT connector, set up on dabble.me.
                        if let connectors = model.me?.aiConnectors {
                            Link(destination: connectors.guideUrl) {
                                SearchRow(icon: "slab-claude", title: "Chat with your journal",
                                          message: "Ask questions and understand patterns by connecting to your AI assistant like Claude or ChatGPT.")
                            }
                            .accessibilityLabel("Chat with your journal")
                            .accessibilityHint("Shows how to connect Claude or ChatGPT")
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onAppear { Task { await loadHashtags() } }
        } else if isSearching && results.isEmpty {
            ProgressView()
        } else if let error, results.isEmpty {
            ContentUnavailableView("Search failed", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if results.isEmpty {
            ContentUnavailableView.search(text: submitted)
        } else {
            // The count scrolls away; each month's results sit under a sticky "Month YYYY"
            // (pinned just under the search field), like the Journal.
            ScrollViewReader { proxy in
            List {
                Text(totalCount == 1 ? "1 matching entry" : "\(totalCount.formatted()) matching entries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                ForEach(resultMonths, id: \.key) { month in
                    Section {
                        ForEach(month.entries) { entry in
                            TimelineEntryRow(entry: entry, isExpanded: expanded.contains(entry.id), actions: actions,
                                             onExpand: { withAnimation(.snappy(duration: 0.25)) { _ = expanded.insert(entry.id) } },
                                             onOpen: { path.append(EntryRoute(id: entry.id)) })
                            .entryRowMenu(entry, actions: actions) { path.append(EntryRoute(id: entry.id)) }
                            .timelineRowLayout()
                            .task {
                                if entry.id == results.last?.id { await search(reset: false) }
                            }
                        }
                    } header: {
                        MonthHeader(title: month.title)
                    }
                }
                if nextPage != nil {
                    ProgressView().frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .listStyle(.plain)
            .timelinePinsDates()
            // Pull to reset: collapses expanded results and runs the search again.
            .refreshable {
                withAnimation(.snappy(duration: 0.25)) { expanded = [] }
                query = submitted
                await search(reset: true, keepingResults: true)
            }
            // The Journal's timeline scrubber, over the months the results (loaded so far) fall
            // in: drag to a month, or tap it for the calendar.
            .scrollIndicators(scrubberMonths.count >= 3 ? .hidden : .automatic)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let scrollable = geometry.contentSize.height - geometry.containerSize.height
                return scrollable > 0 ? min(max((geometry.contentOffset.y + geometry.contentInsets.top) / scrollable, 0), 1) : 0
            } action: { _, progress in
                scrollProgress = progress
            }
            .onScrollPhaseChange { _, phase in isScrolling = phase.isScrolling }
            .overlay(alignment: .trailing) {
                if scrubberMonths.count >= 3 {
                    TimelineScrubber(months: scrubberMonths, progress: scrollProgress, isScrolling: isScrolling, onSelect: { month in
                        if let first = resultMonths.first(where: { $0.key == month.key })?.entries.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }, onTap: {
                        model.showsDayPicker = true
                    })
                }
            }
            }
        }
    }

    /// Results in their order (newest first), grouped by month for the sticky headers.
    private var resultMonths: [(key: String, title: String, entries: [EntrySummary])] {
        var months: [(key: String, title: String, entries: [EntrySummary])] = []
        for entry in results {
            let key = entry.day?.monthKey ?? String(entry.date.prefix(7))
            if months.last?.key == key {
                months[months.count - 1].entries.append(entry)
            } else {
                months.append((key, entry.day?.monthTitle ?? key, [entry]))
            }
        }
        return months
    }

    /// The results' months with how many results each has, for the scrubber.
    private var scrubberMonths: [MonthCount] {
        resultMonths.compactMap { month in
            let parts = month.key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return MonthCount(year: parts[0], month: parts[1], count: month.entries.count)
        }
    }

    private func loadHashtags() async {
        if let tags = try? await model.topHashtags() { hashtags = tags }
    }

    private func clear() {
        submitted = ""
        results = []
        nextPage = nil
        totalCount = 0
        error = nil
    }

    /// `keepingResults`: a pull to reset keeps the list up (and its pull running) until the new results come.
    private func search(reset: Bool, keepingResults: Bool = false) async {
        let term = reset ? query.trimmingCharacters(in: .whitespaces) : submitted
        guard !term.isEmpty, !isSearching else { return }
        let page: Int
        if reset {
            page = 1
        } else if let next = nextPage {
            page = next
        } else {
            return
        }

        isSearching = true
        defer { isSearching = false }
        if reset {
            submitted = term
            if !keepingResults { results = [] }
        }
        do {
            let result = try await model.search(term, page: page)
            guard term == submitted else { return } // a newer search started meanwhile
            results = reset ? result.entries : results + result.entries
            nextPage = result.nextPage
            totalCount = result.totalCount
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The past year's hashtags, sized by how often they're used. Tap one to search for it.
struct HashtagCloud: View {
    let hashtags: [HashtagCount]
    let onSelect: (String) -> Void

    var body: some View {
        let counts = hashtags.map(\.count)
        let low = Double(counts.min() ?? 1)
        let high = Double(counts.max() ?? 1)
        FlowLayout(spacing: 8) {
            ForEach(hashtags.sorted { $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending }) { hashtag in
                // 0...1 by frequency, on a square-root scale so one huge tag doesn't flatten the rest.
                let weight = high > low ? sqrt((Double(hashtag.count) - low) / (high - low)) : 0.5
                Button {
                    onSelect(hashtag.tag)
                } label: {
                    Text("#\(hashtag.tag)")
                        .font(.system(size: 14 + 12 * weight, weight: weight > 0.6 ? .semibold : .regular, design: .serif))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint.opacity(0.08 + 0.14 * weight), in: .capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel("#\(hashtag.tag)")
                .accessibilityValue(hashtag.count == 1 ? "1 entry" : "\(hashtag.count) entries")
                .accessibilityHint("Searches for this hashtag")
            }
        }
    }
}

/// Lays out views left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// A tappable card on Search's start screen: an icon, a title over a line about it, and an arrow.
private struct SearchRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            appIcon(icon)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            appIcon("slab-angle-right")
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
    }
}

/// Stats' pointer to the Claude/ChatGPT connector (set up on dabble.me), for what the numbers
/// don't do. With `prompt`, something to ask once connected, with a Copy button.
struct ConnectorCallout: View {
    let title: String
    let message: String
    let guide: URL
    var prompt: String? = nil
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, icon: "slab-claude")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let prompt {
                Text(prompt)
                    .font(.system(.footnote, design: .serif))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color("Paper"), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    .accessibilityLabel("Prompt: \(prompt)")
            }
            // The two buttons the same size; the copy icon small, beside its words.
            HStack(spacing: 10) {
                if let prompt {
                    Button {
                        UIPasteboard.general.string = prompt
                        copied = true
                    } label: {
                        HStack(spacing: 5) {
                            appIcon(copied ? "slab-check" : "slab-copy")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 13, height: 13)
                            Text(copied ? "Copied" : "Copy Prompt")
                        }
                        .frame(minHeight: 20)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Link(destination: guide) {
                    Text("Connect AI Assistant")
                        .frame(minHeight: 20)
                }
                .buttonStyle(.bordered)
            }
            .buttonBorderShape(.capsule)
            .font(.footnote.weight(.semibold))
            .controlSize(.regular)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 14))
        .sensoryFeedback(.success, trigger: copied)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
