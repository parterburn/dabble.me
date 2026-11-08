import SwiftUI

struct EntryRoute: Hashable {
    let id: Int
}

struct JournalView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var composing = false
    @State private var showingProInfo = false
    @State private var randomError: String?

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Journal")
                .navigationDestination(for: EntryRoute.self) { EntryDetailView(entryID: $0.id) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Random Entry", systemImage: "shuffle") { Task { await openRandom() } }
                            .disabled(model.entries.isEmpty)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Entry", systemImage: "square.and.pencil") { startWriting() }
                    }
                }
                .sheet(isPresented: $composing) { ComposeView(mode: .new) }
                .sheet(isPresented: $showingProInfo) { ProInfoView(feature: .writing) }
                .alert("Couldn't open an entry", isPresented: .present($randomError)) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(randomError ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.entries.isEmpty {
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
                    Label("No entries yet", systemImage: "envelope.open")
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
            List {
                if let error = model.timelineError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !model.onThisDay.isEmpty {
                    Section("On This Day") {
                        ForEach(model.onThisDay) { entry in
                            NavigationLink(value: EntryRoute(id: entry.id)) {
                                EntryRow(entry: entry, showsYear: true)
                            }
                        }
                    }
                }

                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.entries) { entry in
                            NavigationLink(value: EntryRoute(id: entry.id)) {
                                EntryRow(entry: entry)
                            }
                            .task { await model.loadMoreIfNeeded(after: entry) }
                        }
                    }
                }

                if model.nextPage != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .refreshable { await model.refresh() }
        }
    }

    private var sections: [MonthSection] {
        var result: [MonthSection] = []
        for entry in model.entries {
            let key = String(entry.date.prefix(7))
            if result.last?.id == key {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append(MonthSection(id: key, title: entry.day?.monthTitle ?? key, entries: [entry]))
            }
        }
        return result
    }

    private func startWriting() {
        if model.me?.canWrite == true {
            composing = true
        } else {
            showingProInfo = true
        }
    }

    private func openRandom() async {
        do {
            let entry = try await model.randomEntry()
            path.append(EntryRoute(id: entry.id))
        } catch is CancellationError {
        } catch {
            randomError = error.localizedDescription
        }
    }
}

private struct MonthSection: Identifiable {
    let id: String
    let title: String
    var entries: [EntrySummary]
}

struct EntryRow: View {
    let entry: EntrySummary
    var showsYear = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(entry.day?.weekdayShort.uppercased() ?? "")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.day?.dayNumber ?? "")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 42)

            VStack(alignment: .leading, spacing: 4) {
                if showsYear, let year = entry.day?.year {
                    Text(year)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Text(entry.excerpt.isEmpty ? "📷 Photo" : entry.excerpt)
                    .font(.system(.body, design: .serif))
                    .lineLimit(3)
                if !entry.hashtags.isEmpty {
                    Text(entry.hashtags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if entry.imageProcessing || entry.imageURL != nil {
                EntryPhoto(url: entry.imageURL, isProcessing: entry.imageProcessing, size: .thumbnail)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(entry.day?.long ?? entry.date). \(entry.excerpt)\(entry.imageProcessing ? ". Photos processing." : entry.imageURL != nil ? ". Has photo." : "")"))
    }
}

extension Binding where Value == Bool {
    /// `true` while `optional` is non-nil; setting `false` clears it. For alerts driven by an error message.
    static func present<T: Sendable>(_ optional: Binding<T?>) -> Binding<Bool> {
        Binding(get: { optional.wrappedValue != nil }, set: { if !$0 { optional.wrappedValue = nil } })
    }
}
