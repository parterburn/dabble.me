import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
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

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.me?.canSearch == false {
                    ProInfoView(feature: .search, showsDoneButton: false)
                } else {
                    resultsList
                        // Always visible at the top, not tucked away when the results scroll.
                        .searchable(text: $query, isPresented: $isSearchActive,
                                    placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your journal")
                        .searchFocused($isSearchFocused)
                        // With results showing, search is already "active", so focus the field itself.
                        .onChange(of: model.searchFocusRequest) {
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
            if hashtags.isEmpty {
                ContentUnavailableView {
                    Label("Search your journal", icon: "slab-search")
                } description: {
                    Text("Find a word, a #hashtag, an \"exact phrase\", or either of two words with hiking OR camping.")
                }
                .task { await loadHashtags() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your Hashtags This Year")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        HashtagCloud(hashtags: hashtags) { tag in
                            query = "#\(tag)"
                            Task { await search(reset: true) }
                        }
                        Text("Search for a word, a #hashtag, an \"exact phrase\", or either of two words with hiking OR camping.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    .padding()
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await loadHashtags() }
            }
        } else if isSearching && results.isEmpty {
            ProgressView()
        } else if let error, results.isEmpty {
            ContentUnavailableView("Search failed", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if results.isEmpty {
            ContentUnavailableView.search(text: submitted)
        } else {
            List {
                Section {
                    ForEach(results) { entry in
                        TimelineEntryRow(entry: entry, showsYear: true, isExpanded: expanded.contains(entry.id), actions: actions) {
                            if expanded.contains(entry.id) {
                                path.append(EntryRoute(id: entry.id))
                            } else {
                                withAnimation(.snappy(duration: 0.25)) { _ = expanded.insert(entry.id) }
                            }
                        }
                        .entryPreview(entry) { path.append(EntryRoute(id: entry.id)) }
                        .task {
                            if entry.id == results.last?.id { await search(reset: false) }
                        }
                    }
                    if nextPage != nil {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } header: {
                    Text(totalCount == 1 ? "1 entry" : "\(totalCount.formatted()) entries")
                }
            }
            .listStyle(.plain)
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

    private func search(reset: Bool) async {
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
            results = []
        }
        do {
            let result = try await model.search(term, page: page)
            guard term == submitted else { return } // a newer search started meanwhile
            results += result.entries
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
