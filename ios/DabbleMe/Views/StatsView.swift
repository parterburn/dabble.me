import Charts
import SwiftUI

/// Journal > Stats: totals, streaks, a year of writing days, recent months and the past
/// year's hashtags. Counts only; it never shows entry text.
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @State private var stats: JournalStats?
    @State private var error: String?

    var body: some View {
        Group {
            if let stats {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        tiles(stats)
                        StatsCard(title: "Past Year") {
                            WritingHeatmap(days: Set(stats.writingDays), today: model.today?.day ?? JournalDay(localDate: .now))
                            Text(stats.writingDays.count == 1 ? "1 day written in the past year" : "\(stats.writingDays.count.formatted()) days written in the past year")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        StatsCard(title: "Entries per Month") {
                            MonthBars(months: stats.months)
                        }
                        if !stats.topHashtags.isEmpty {
                            StatsCard(title: "Top Hashtags This Year") {
                                HashtagBars(hashtags: stats.topHashtags, canSearch: model.me?.canSearch == true) { tag in
                                    model.search(hashtag: tag)
                                }
                            }
                        }
                        footer(stats)
                    }
                    .padding()
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't load your stats", icon: "slab-signal-bars")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .refreshable { await load() }
        .task { if stats == nil { await load() } }
    }

    private func tiles(_ stats: JournalStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(value: stats.totalEntries.formatted(), label: stats.totalEntries == 1 ? "Entry" : "Entries", icon: "slab-book")
            StatTile(value: stats.totalWords.formatted(.number.notation(.compactName)), label: "Words", icon: "slab-language")
            StatTile(value: days(stats.currentStreak), label: "Current Streak", icon: "slab-fire")
            StatTile(value: days(stats.longestStreak), label: "Longest Streak", icon: "slab-trophy")
            StatTile(value: stats.entriesThisYear.formatted(), label: "Entries This Year", icon: "slab-calendar")
            StatTile(value: stats.photoEntries.formatted(), label: "Days with Photos", icon: "slab-images")
        }
    }

    @ViewBuilder
    private func footer(_ stats: JournalStats) -> some View {
        let parts = [
            stats.firstEntryDay.map { "Writing since \($0.formatted(.dateTime.month(.wide).year()))" },
            stats.busiestWeekday.map { "Most often on \($0)s" },
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count.formatted()) days"
    }

    private func load() async {
        do {
            stats = try await model.stats()
            error = nil
        } catch is CancellationError {
        } catch {
            if stats == nil { self.error = error.localizedDescription }
        }
    }
}

private struct StatsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            appIcon(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(.tint)
            Text(value)
                .font(.system(.title, design: .serif, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// A year of days as week columns (Sunday on top), newest on the right, like a contribution graph.
private struct WritingHeatmap: View {
    let days: Set<String>
    let today: JournalDay

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    private var weeks: [[JournalDay?]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let end = today.date
        guard let start = calendar.date(byAdding: .day, value: -364, to: end) else { return [] }
        // Start each column on a Sunday.
        let weekday = calendar.component(.weekday, from: start)
        guard let firstSunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: start) else { return [] }
        var weeks: [[JournalDay?]] = []
        var day = firstSunday
        while day <= end {
            var week: [JournalDay?] = []
            for _ in 0..<7 {
                week.append(day >= start && day <= end ? JournalDay(localDate: day, calendar: calendar) : nil)
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
            weeks.append(week)
        }
        return weeks
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(fill(for: week[index]))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .defaultScrollAnchor(.trailing)
        .scrollIndicators(.hidden)
        .accessibilityElement()
        .accessibilityLabel("Writing days in the past year")
        .accessibilityValue("\(days.count) days with an entry")
    }

    private func fill(for day: JournalDay?) -> AnyShapeStyle {
        guard let day else { return AnyShapeStyle(.clear) }
        return days.contains(day.iso) ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.14))
    }
}

/// One bar per month (a single series, so no legend). Tap or drag to read a month's count.
private struct MonthBars: View {
    let months: [MonthCount]
    @State private var selected: String?

    var body: some View {
        Chart(months) { month in
            BarMark(x: .value("Month", month.key), y: .value("Entries", month.count), width: .ratio(0.6))
                .clipShape(.rect(topLeadingRadius: 4, topTrailingRadius: 4))
                .foregroundStyle(selected == nil || selected == month.key ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.35)))
                .annotation(position: .top, spacing: 4) {
                    if selected == month.key {
                        Text(month.count.formatted())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
        }
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: months.map(\.key)) { value in
                AxisValueLabel {
                    if let key = value.as(String.self) {
                        Text(JournalDay(key + "-01")?.formatted(.dateTime.month(.narrow)) ?? "")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .frame(height: 160)
        .accessibilityElement()
        .accessibilityLabel("Entries per month")
        .accessibilityValue(months.map { "\(MonthCount(key: $0.key, count: 0)?.shortTitle ?? $0.key): \($0.count)" }.joined(separator: ", "))
    }
}

private struct HashtagBars: View {
    let hashtags: [HashtagCount]
    let canSearch: Bool
    let onSelect: (String) -> Void

    var body: some View {
        let most = max(hashtags.map(\.count).max() ?? 1, 1)
        VStack(spacing: 10) {
            ForEach(hashtags) { hashtag in
                Button {
                    onSelect(hashtag.tag)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("#\(hashtag.tag)")
                                .foregroundStyle(canSearch ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            Spacer()
                            Text(hashtag.count.formatted())
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(.tint.opacity(0.35))
                                .frame(width: max(4, proxy.size.width * CGFloat(hashtag.count) / CGFloat(most)))
                        }
                        .frame(height: 4)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSearch)
                .accessibilityLabel("#\(hashtag.tag), \(hashtag.count) entries")
            }
        }
    }
}
