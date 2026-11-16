import SwiftUI
import WidgetKit

@main
struct DabbleMeWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        // (The same kind as before it could be edited: widgets already out keep their place.)
        AppIntentConfiguration(kind: "Today", intent: TodayWidgetIntent.self, provider: Provider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.paper }
        }
        .configurationDisplayName("Today")
        .description("Today's date and a nudge to write (on the Lock Screen, your entries this year). Touch and hold the widget to choose what shows beside the date.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry { .placeholder }

    func snapshot(for configuration: TodayWidgetIntent, in context: Context) async -> WidgetEntry {
        context.isPreview ? .placeholder : entry(at: .now, showing: configuration.show)
    }

    func timeline(for configuration: TodayWidgetIntent, in context: Context) async -> Timeline<WidgetEntry> {
        // Today now, then a fresh day at midnight (the app reloads the widget when it learns more).
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        return Timeline(entries: [entry(at: .now, showing: configuration.show), entry(at: midnight, showing: configuration.show)],
                        policy: .after(midnight))
    }

    private func entry(at date: Date, showing option: WidgetShowOption) -> WidgetEntry {
        guard let snapshot = WidgetSnapshot.load() else {
            return WidgetEntry(date: date, signedIn: false, wroteToday: false, yearCount: 0, memories: nil, prompt: nil)
        }
        let state = snapshot.state(on: date)
        let isToday = snapshot.day == WidgetSnapshot.iso(date)
        // This widget's own choice, or the app's.
        let content = option.content ?? WidgetSnapshot.content
        // The look back planned for the day (today's, or a day the app hasn't been opened on
        // yet). None planned (nothing to look back on): the prompt, when there's one.
        let rewind = snapshot.rewind(on: date)
        if content.source == .rewind, rewind.known {
            let day = rewind.day
            let showsEntry = content == .memoryEntry
            return WidgetEntry(date: date, signedIn: true, wroteToday: state.wroteToday, yearCount: state.yearCount, lastFiveDays: snapshot.lastFiveDays(on: date),
                               memories: day?.memories, prompt: isToday ? snapshot.prompt : nil,
                               memoryNote: content == .memoryCount ? day?.memoryNote : nil,
                               entryTitle: showsEntry ? day?.entryTitle : nil,
                               entryText: showsEntry ? day?.entryText : nil,
                               entryID: showsEntry ? day?.entryID : nil,
                               photo: showsEntry ? day?.entryPhoto.flatMap(Self.photo(named:)) : nil)
        }
        let shown = isToday ? snapshot.shown(for: content) : nil
        return WidgetEntry(date: date, signedIn: true, wroteToday: state.wroteToday, yearCount: state.yearCount, lastFiveDays: snapshot.lastFiveDays(on: date),
                           memories: content.source == .rewind ? state.memories : nil,
                           prompt: isToday ? snapshot.prompt : nil,
                           memoryNote: isToday && content == .memoryCount ? snapshot.memoryNote : nil,
                           entryTitle: shown?.title, entryText: shown?.text, entryID: shown?.id,
                           photo: shown?.photo.flatMap(Self.photo(named:)))
    }

    /// The entry's photo copy from the App Group (the app saves it small for the widget).
    private static func photo(named name: String) -> UIImage? {
        guard let url = WidgetSnapshot.photoURL(named: name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

struct TodayWidgetView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        TodayWidgetContent(entry: entry, family: family)
            // Today, written or not: writing, editing and reading all start from there.
            .widgetURL(WidgetSnapshot.todayURL)
    }
}
