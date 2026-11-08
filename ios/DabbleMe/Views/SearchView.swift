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

    var body: some View {
        NavigationStack {
            Group {
                if model.me?.canSearch == false {
                    ProInfoView(feature: .search, showsDoneButton: false)
                } else {
                    resultsList
                        .searchable(text: $query, prompt: "Search your journal")
                        .onSubmit(of: .search) { Task { await search(reset: true) } }
                        .onChange(of: query) { _, newValue in
                            if newValue.isEmpty { clear() }
                        }
                        .onChange(of: model.searchRequest, initial: true) { _, request in
                            guard let request else { return }
                            model.searchRequest = nil
                            query = request
                            Task { await search(reset: true) }
                        }
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: EntryRoute.self) { EntryDetailView(entryID: $0.id) }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if submitted.isEmpty {
            ContentUnavailableView {
                Label("Search your journal", systemImage: "text.magnifyingglass")
            } description: {
                Text("Find a word, a #hashtag, an \"exact phrase\", or either of two words with hiking OR camping.")
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
                        NavigationLink(value: EntryRoute(id: entry.id)) {
                            EntryRow(entry: entry, showsYear: true)
                        }
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
