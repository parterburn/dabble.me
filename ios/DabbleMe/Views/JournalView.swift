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
    @State private var scrollProgress: CGFloat = 0
    @State private var isScrolling = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Journal")
                .navigationDestination(for: EntryRoute.self) { EntryDetailView(entryID: $0.id) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Random Entry", systemImage: "shuffle") { Task { await openRandom() } }
                            .disabled(model.months.isEmpty)
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
                    Section {
                        monthRows(month)
                    } header: {
                        MonthHeader(title: month.title)
                            .onAppear { model.monthAppeared(month.key) }
                            .onDisappear { model.monthDisappeared(month.key) }
                    }
                }
            }
            .listStyle(.plain)
            .contentMargins(.trailing, 20, for: .scrollContent) // room for the scrubber
            .refreshable { await model.refresh() }
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
                    TimelineScrubber(months: model.months, progress: scrollProgress, isScrolling: isScrolling) { month in
                        // Jump to the month's first row: its first entry if loaded, else its first placeholder.
                        if let first = model.monthEntries[month.key]?.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        } else {
                            proxy.scrollTo(PlaceholderID(month: month.key, index: 0), anchor: .top)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func monthRows(_ month: MonthCount) -> some View {
        if let entries = model.monthEntries[month.key] {
            ForEach(entries) { entry in
                NavigationLink(value: EntryRoute(id: entry.id)) {
                    EntryRow(entry: entry)
                }
            }
            .task {
                // Reload a month a refresh marked stale once it's back on screen.
                guard model.isStale(month.key) else { return }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await model.loadMonth(month.key)
            }
        } else {
            // Placeholders sized like real rows keep scrolling (and the scrubber) proportional.
            ForEach(0..<month.count, id: \.self) { index in
                EntryRowPlaceholder()
                    .id(PlaceholderID(month: month.key, index: index))
            }
            .task {
                // Wait until the month settles on screen, so flicking or scrubbing past it
                // doesn't fire a request for every month along the way.
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await model.loadMonth(month.key)
            }
        }
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

private struct PlaceholderID: Hashable {
    let month: String
    let index: Int
}

private struct MonthHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct EntryRowPlaceholder: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 42, height: 40)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 14)
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 180, height: 14)
            }
        }
        .padding(.vertical, 4)
        .frame(height: 72, alignment: .top)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
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
                    .multilineTextAlignment(.leading)
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
