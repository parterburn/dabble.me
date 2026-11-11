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
        StaticConfiguration(kind: "Today", provider: Provider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.paper }
        }
        .configurationDisplayName("Today")
        .description("Today's date and a nudge to write (on the Lock Screen, your entries this year). Choose what shows beside the date in the app's Settings.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        // Today now, then a fresh day at midnight (the app reloads the widget when it learns more).
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        completion(Timeline(entries: [entry(at: .now), entry(at: midnight)], policy: .after(midnight)))
    }

    private func entry(at date: Date) -> WidgetEntry {
        guard let snapshot = WidgetSnapshot.load() else {
            return WidgetEntry(date: date, signedIn: false, wroteToday: false, yearCount: 0, memories: nil, prompt: nil)
        }
        let state = snapshot.state(on: date)
        let isToday = snapshot.day == WidgetSnapshot.iso(date)
        let content = WidgetSnapshot.content
        let showsEntry = isToday && content.showsPreviews
        return WidgetEntry(date: date, signedIn: true, wroteToday: state.wroteToday, yearCount: state.yearCount,
                           memories: content.source == .rewind ? state.memories : nil,
                           prompt: isToday ? snapshot.prompt : nil,
                           memoryNote: isToday && content == .memoryCount ? snapshot.memoryNote : nil,
                           entryTitle: showsEntry ? snapshot.entryTitle : nil,
                           entryText: showsEntry ? snapshot.entryText : nil,
                           entryID: showsEntry ? snapshot.entryID : nil,
                           photo: showsEntry ? snapshot.entryPhoto.flatMap(Self.photo(named:)) : nil)
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
            .widgetURL(entry.wroteToday ? WidgetSnapshot.todayURL : WidgetSnapshot.writeURL)
    }
}
