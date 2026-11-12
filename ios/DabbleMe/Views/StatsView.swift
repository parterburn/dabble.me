import Charts
import SwiftUI

/// Journal > Stats: totals, the longest streak, a year of writing days (this year or an earlier one), recent months and the past
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
                        if showsOverview(stats) {
                            StatsOverview(stats: stats, today: model.today?.day ?? JournalDay(localDate: .now))
                        }
                        YearCard(stats: stats, today: model.today?.day ?? JournalDay(localDate: .now))
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
                        if let connectors = model.me?.aiConnectors {
                            ConnectorCallout(
                                title: "Sentiment analysis",
                                message: "Analyze your writing over time with the Claude or ChatGPT plugin.",
                                guide: connectors.guideUrl,
                                prompt: Self.sentimentPrompt
                            )
                        }
                        if !showsOverview(stats) { footer(stats) } // the overview says these
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

    /// Something to ask Claude or ChatGPT with the Dabble Me connector on.
    static let sentimentPrompt = "Using my Dabble Me journal, do a sentiment analysis of my entries from the past year: how my mood trended month by month, what lifted it and what weighed on it, and the people, places and themes that show up when I'm at my best."

    private func tiles(_ stats: JournalStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(value: stats.totalEntries.formatted(), label: stats.totalEntries == 1 ? "Entry" : "Entries", icon: "slab-book")
            StatTile(value: stats.photoEntries.formatted(), label: "Photos", icon: "slab-images")
            // The longest streak, with the year it was in ("Streak • 2024"). The year's own entries
            // are beside the year below.
            StatTile(value: days(stats.longestStreak), label: stats.longestStreakYear.map { "Streak • \(String($0))" } ?? "Longest Streak",
                     icon: "slab-fire")
            StatTile(value: stats.totalWords.formatted(.number.notation(.compactName)), label: "Words", icon: "slab-language")
        }
    }

    /// With Apple Intelligence on and a few entries to go on, an overview under the tiles.
    private func showsOverview(_ stats: JournalStats) -> Bool {
        stats.totalEntries >= 5 && JournalIntelligence.isEnabled(for: model.me)
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

/// A few sentences on the stats, written on the device from the numbers alone (no entry text),
/// once a day (kept for that day, and redone if the entry count changes). In a well with a
/// minimum height, so the page doesn't jump when it arrives.
private struct StatsOverview: View {
    let stats: JournalStats
    let today: JournalDay
    @AppStorage("ai.stats.key") private var savedKey = ""
    @AppStorage("ai.stats.text") private var savedText = ""
    @State private var failed = false

    private var key: String { "2|\(today.iso)|\(stats.totalEntries)|\(stats.totalWords)" }
    private var text: String? { savedKey == key && !savedText.isEmpty ? savedText : nil }
    /// What shows if the model can't write one: the plainest facts, as before.
    private var fallback: String { JournalIntelligence.statsFacts(stats, today: today).prefix(3).joined(separator: " ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Overview", icon: "slab-sparkles")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tint)
            if let text = text ?? (failed ? fallback : nil) {
                Text(text)
                    .font(.system(.callout, design: .serif))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityIdentifier("StatsOverview")
            } else {
                Text("A few sentences about how and when you write, from the numbers on this page, are being written on your device now.")
                    .font(.system(.callout, design: .serif))
                    .lineSpacing(3)
                    .redacted(reason: .placeholder)
                    .accessibilityLabel("Writing an overview of your stats")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(Color("Paper"), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
        .animation(.easeOut(duration: 0.25), value: text)
        .task(id: key) {
            guard text == nil else { return }
            failed = false
            do {
                let written = try await JournalIntelligence.statsOverview(facts: JournalIntelligence.statsFacts(stats, today: today))
                savedText = written
                savedKey = key
            } catch is CancellationError {
            } catch {
                failed = true
            }
        }
    }
}

/// A year of writing days. Its title is the year ("2026"), with a small chevron when there are
/// earlier years to choose from a menu. On the right, the year's entries and the share of its
/// days with one ("37 entries • 11% of days"); for this year that's of the days so far, and the
/// days still to come are the paler squares.
private struct YearCard: View {
    let stats: JournalStats
    let today: JournalDay
    @Environment(AppModel.self) private var model
    /// The year shown; nil is this year.
    @State private var picked: Int?
    /// Earlier years' days, loaded as they're picked.
    @State private var loaded: [Int: Set<String>] = [:]
    @State private var failed: Int?

    private var thisYear: Int { Int(today.year) ?? 0 }
    private var year: Int { picked ?? thisYear }
    /// From the first entry's year to this one, newest first.
    private var years: [Int] {
        let first = min(stats.firstEntryDay.flatMap { Int($0.year) } ?? thisYear, thisYear)
        return Array((first...thisYear).reversed())
    }
    /// The year's days with an entry, or nil while an earlier year's are loading.
    private var days: Set<String>? {
        year == thisYear ? Set(stats.writingDays.filter { $0.hasPrefix("\(today.year)-") }) : loaded[year]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                title
                Spacer(minLength: 8)
                summary
            }
            WritingHeatmap(year: year, days: days ?? [], today: today) { day in
                model.statsDay = StatsDay(day: day)
            }
            .id(year) // each year opens at its newest weeks
            if failed == year {
                Text("Couldn't load \(String(year)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: year) { await load(year) }
    }

    @ViewBuilder
    private var title: some View {
        if years.count > 1 {
            Menu {
                Picker("Year", selection: Binding(get: { year }, set: { picked = $0 == thisYear ? nil : $0 })) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(String(year))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    appIcon("slab-angle-down")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 11, height: 11)
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain) // the title's own black and the chevron's grey, not the tint
            .accessibilityLabel("Year, \(String(year))")
            .accessibilityHint("Chooses another year")
        } else {
            Text(String(year))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// "37 entries • 11% of days": the year's entries, and the share of its days with one (for
    /// this year, of the days so far, today included).
    @ViewBuilder
    private var summary: some View {
        if let days {
            let entries = year == thisYear ? max(stats.entriesThisYear, days.count) : days.count
            Text("\(entries == 1 ? "1 entry" : "\(entries.formatted()) entries") • \(Self.percent(days.count, of: dayCount))% of days")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("StatsYearSummary")
        } else if failed != year {
            ProgressView().controlSize(.small)
        }
    }

    /// The year's days: all of them for a finished year, those up to today for this one.
    private var dayCount: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        if year == thisYear { return calendar.ordinality(of: .day, in: .year, for: today.date) ?? 1 }
        return calendar.range(of: .day, in: .year, for: JournalDay("\(year)-06-01")?.date ?? today.date)?.count ?? 365
    }

    /// 100 only for the whole of it; never 0 once there's any.
    static func percent(_ written: Int, of total: Int) -> Int {
        guard written > 0, total > 0 else { return 0 }
        if written >= total { return 100 }
        return min(max(Int((Double(written) * 100 / Double(total)).rounded()), 1), 99)
    }

    private func load(_ year: Int) async {
        guard year != thisYear, loaded[year] == nil else { return }
        failed = nil
        do {
            loaded[year] = Set(try await model.writingDays(year: year))
        } catch is CancellationError {
        } catch {
            failed = year
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
        // The icon beside the number (not above it), in light grey: it labels, it isn't a button.
        HStack(alignment: .center, spacing: 10) {
            appIcon(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// A calendar year of days as week columns (Sunday on top), like a contribution graph and the
/// web's. This year's days still to come are paler, so the grid shows how much of the year is
/// left, and it opens with today a few weeks from its right edge. Month names along the top, Mon / Wed / Fri down the side. Pinch to make the
/// squares bigger (easier to tap a day) or smaller (more of the year at once); the size is kept.
private struct WritingHeatmap: View {
    let year: Int
    let days: Set<String>
    let today: JournalDay
    /// A day with an entry was tapped.
    let onSelect: (JournalDay) -> Void

    @AppStorage("stats.heatmapCell") private var cellSize: Double = 13
    @State private var pinchStart: Double?
    private static let sizes = 9.0...32.0
    private let labelRow: CGFloat = 16

    private var cell: CGFloat { CGFloat(cellSize) }
    private var gap: CGFloat { max(3, (cell * 0.25).rounded()) }

    private var weeks: [[JournalDay?]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let last = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else { return [] }
        let end = last
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

    /// "JAN" over the first column of each month (the year is the card's title).
    private func monthLabels(_ weeks: [[JournalDay?]]) -> [String?] {
        let months = weeks.map { week in week.compactMap { $0 }.first.map { String($0.iso.prefix(7)) } } // "2025-11"
        return months.indices.map { index in
            guard let month = months[index] else { return nil }
            if index == 0 {
                // Skip a sliver of a month at the start: its label would run into the next one.
                return months.prefix(3).allSatisfy { $0 == month } ? monthName(month) : nil
            }
            return months[index - 1] == month ? nil : monthName(month)
        }
    }

    private func monthName(_ key: String) -> String? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let index = Int(parts[1]), (1...12).contains(index) else { return nil }
        return Calendar.current.shortMonthSymbols[index - 1].uppercased() // the reader's language
    }

    var body: some View {
        let weeks = weeks
        HStack(alignment: .top, spacing: 6) {
            weekdayLabels
            ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: gap) {
                        ForEach(Array(monthLabels(weeks).enumerated()), id: \.offset) { _, label in
                            Text(label ?? "")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .frame(width: cell, height: labelRow, alignment: .leading)
                        }
                    }
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { column, week in
                            VStack(spacing: gap) {
                                ForEach(0..<7, id: \.self) { index in
                                    RoundedRectangle(cornerRadius: cell * 0.23)
                                        .fill(fill(for: week[index]))
                                        .frame(width: cell, height: cell)
                                }
                            }
                            .id(column)
                        }
                    }
                    // One tap handler for the grid: the squares are small, so a tap a little off a
                    // written day (on an empty neighbor or a gap) still opens the nearest one.
                    .contentShape(.rect)
                    .gesture(SpatialTapGesture().onEnded { tap in
                        if let day = writtenDay(near: tap.location, in: weeks) { onSelect(day) }
                    })
                }
                .padding(.vertical, 2)
            }
            .defaultScrollAnchor(.trailing)
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(restingColumn(in: weeks), anchor: .trailing) }
            // Resizing keeps the same weeks in view (otherwise it jumps to the year's start).
            .onChange(of: cellSize) { proxy.scrollTo(restingColumn(in: weeks), anchor: .trailing) }
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = pinchStart ?? cellSize
                    pinchStart = start
                    cellSize = min(max(start * value.magnification, Self.sizes.lowerBound), Self.sizes.upperBound)
                }
                .onEnded { _ in pinchStart = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("Writing days in \(String(year))")
        .accessibilityValue("\(days.count) days with an entry")
    }

    /// The column at the grid's right edge when it opens: the year's last, or, this year, a few
    /// weeks past today's, so the days written are in view with the start of what's left.
    private func restingColumn(in weeks: [[JournalDay?]]) -> Int {
        guard let current = weeks.firstIndex(where: { $0.contains { $0?.iso == today.iso } }) else { return weeks.count - 1 }
        return min(current + Self.weeksAhead, weeks.count - 1)
    }
    private static let weeksAhead = 4

    /// Mon, Wed and Fri beside their rows, like the web.
    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                Text(row == 1 ? "Mon" : row == 3 ? "Wed" : row == 5 ? "Fri" : "")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(height: cell)
            }
        }
        .padding(.top, labelRow + 4 + 2)
        .accessibilityHidden(true)
    }

    /// The written day under `point`, or else the closest written one within a square of it.
    private func writtenDay(near point: CGPoint, in weeks: [[JournalDay?]]) -> JournalDay? {
        let pitch = cell + gap
        var best: (day: JournalDay, distance: CGFloat)?
        let column = Int(point.x / pitch), row = Int(point.y / pitch)
        for c in (column - 1)...(column + 1) where weeks.indices.contains(c) {
            for r in (row - 1)...(row + 1) where (0..<7).contains(r) {
                guard let day = weeks[c][r], days.contains(day.iso) else { continue }
                let center = CGPoint(x: CGFloat(c) * pitch + cell / 2, y: CGFloat(r) * pitch + cell / 2)
                let distance = hypot(center.x - point.x, center.y - point.y)
                if distance <= pitch * 1.1, distance < (best?.distance ?? .infinity) { best = (day, distance) }
            }
        }
        return best?.day
    }

    private func fill(for day: JournalDay?) -> AnyShapeStyle {
        guard let day else { return AnyShapeStyle(.clear) }
        if days.contains(day.iso) { return AnyShapeStyle(.tint) }
        // Days still to come are paler than the ones that went by unwritten.
        return AnyShapeStyle(Color.secondary.opacity(day > today ? 0.06 : 0.14))
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

/// A day's entries, from Stats → Past Year, in a sheet like A Random Memory: each one whole and
/// scrollable, with Open to go to it in the Journal.
/// A day tapped in Stats → Past Year or picked in Jump to a Day (`AppModel.statsDay`).
struct StatsDay: Identifiable {
    let day: JournalDay
    var id: String { day.iso }
}

struct DayEntriesSheet: View {
    let day: JournalDay
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [EntryDetail]?
    @State private var error: String?
    /// The day of the entry stepped to with the arrows beside Open (nil: the day it opened on).
    @State private var steppedTo: JournalDay?
    @State private var isStepping = false
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The calendar picks another day: this closes and it opens, on this day's month.
            SheetHeader(title: "Jump to a Day") {
                SheetIconButton(icon: "slab-calendar", label: "Jump to a Day") {
                    model.dayPickerOpensOn = steppedTo ?? day
                    model.reopensDayPicker = true
                    dismiss()
                }
                .accessibilityIdentifier("DayDrawerCalendar")
            }
            if let entries {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 12) {
                                // "Sunday, Nov 9, 2025 · 1 year ago", as A Random Memory dates its entry.
                                Text(model.dateLine(for: entry.day, fallback: entry.date))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tint)
                                if let document = entry.document {
                                    DocumentText(blocks: RichText.droppingTrailing(hashtags: (entry.datedHashtags ?? []).map(\.tag), songLinks: !entry.songs.isEmpty, from: document), font: .system(size: bodySize * textSize.scale, design: fontStyle.design),
                                                 scale: textSize.scale, bodySize: bodySize)
                                } else {
                                    Text(RichText.linkingURLs(in: RichText.linkingHashtags(in: AttributedString.journal(RichText.droppingTrailing(hashtags: (entry.datedHashtags ?? []).map(\.tag), songLinks: !entry.songs.isEmpty, from: entry.bodyText)))))
                                        .font(.system(size: bodySize * textSize.scale, design: fontStyle.design))
                                        .lineSpacing(5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if !entry.songs.isEmpty {
                                    SongList(songs: entry.songs)
                                }
                                if let dated = entry.datedHashtags, !dated.isEmpty {
                                    DatedHashtagRow(hashtags: dated)
                                }
                                if entry.imageProcessing || entry.imageURL != nil {
                                    EntryPhoto(url: entry.imageURL, isProcessing: entry.imageProcessing, day: entry.day)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                // Links work here too: a #tag closes this and searches for it; a web page opens (dabble.me's
                // in the app).
                .environment(\.openURL, OpenURLAction { url in
                    if let tag = RichText.hashtag(from: url) {
                        dismiss()
                        model.search(hashtag: tag)
                        return .handled
                    }
                    return WebLinks.open(url)
                })
                // Always in view under the entry, as in A Random Memory: Open, between the
                // entries before and after this one.
                EntryStepBar(entry: entries.first, isLoading: isStepping) { id in
                    Task { await step(to: id) }
                } open: {
                    // The Journal opens it (this sheet also comes up over Search).
                    guard let entry = entries.first else { return }
                    model.selectedTab = .journal
                    model.openEntryRequest = entry.id
                    dismiss()
                }
            } else if let error {
                ContentUnavailableView("Couldn't load this day", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .padding([.horizontal, .top], 20)
        // The Open bar sits at the sheet's foot, as far from its bottom edge as from its sides
        // (the home indicator's safe area on top of the padding left a gap under it).
        .padding(.bottom, 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .bottom)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    /// The entry before or after: it takes the sheet, under its own date.
    private func step(to id: Int) async {
        guard !isStepping else { return }
        isStepping = true
        defer { isStepping = false }
        do {
            let entry = try await model.entry(id: id)
            withAnimation(.snappy) {
                entries = [entry]
                steppedTo = entry.day
            }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The day's entries, each in full.
    private func load() async {
        do {
            let loaded = try await model.entries(on: day)
            if loaded.isEmpty { error = "No entries on this day." } else { entries = loaded }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
