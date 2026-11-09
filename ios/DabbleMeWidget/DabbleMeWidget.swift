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
        .description("Your writing streak and a nudge to write. Shows an entry only if you turn on Show Entries in Widget in the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let signedIn: Bool
    let wroteToday: Bool
    let streak: Int
    let memories: Int?
    let prompt: String?
    /// An entry to look back on (only with "Show Entries in Widget" on in the app).
    var entryTitle: String? = nil
    var entryText: String? = nil

    static let placeholder = WidgetEntry(date: .now, signedIn: true, wroteToday: false, streak: 12, memories: nil,
                                         prompt: "What made you smile today?")
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
            return WidgetEntry(date: date, signedIn: false, wroteToday: false, streak: 0, memories: nil, prompt: nil)
        }
        let state = snapshot.state(on: date)
        let isToday = snapshot.day == WidgetSnapshot.iso(date)
        let showsEntry = isToday && WidgetSnapshot.showsMemories
        return WidgetEntry(date: date, signedIn: true, wroteToday: state.wroteToday, streak: state.streak,
                           memories: WidgetSnapshot.showsMemories ? state.memories : nil,
                           prompt: isToday ? snapshot.prompt : nil,
                           entryTitle: showsEntry ? snapshot.entryTitle : nil,
                           entryText: showsEntry ? snapshot.entryText : nil)
    }
}

struct TodayWidgetView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: Text(entry.wroteToday ? "✓ \(streakText)" : "Write today · \(streakText)")
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(entry.wroteToday ? WidgetSnapshot.todayURL : WidgetSnapshot.writeURL)
    }

    private var streakText: String {
        entry.streak == 1 ? "1-day streak" : entry.streak > 1 ? "\(entry.streak)-day streak" : "No streak yet"
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dabble Me")
                .font(.system(.caption, design: .serif, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if entry.signedIn {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(Color.sage)
                    Text(entry.streak.formatted())
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .contentTransition(.numericText())
                }
                Text(entry.streak == 1 ? "day in a row" : "days in a row")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                status
            } else {
                Text("Sign in to see your streak.")
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var status: some View {
        if entry.wroteToday {
            Label("Written today", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sage)
        } else {
            Label("Write today", systemImage: "square.and.pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sage)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            small
                .frame(maxWidth: 130)
            VStack(alignment: .leading, spacing: 8) {
                if let title = entry.entryTitle, let text = entry.entryText {
                    Label(title, systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(text)
                        .font(.system(.subheadline, design: .serif))
                        .lineLimit(4)
                } else if let memories = entry.memories {
                    Label("On This Day", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(memories == 1 ? "You have a memory from this day." : "You have \(memories) memories from this day.")
                        .font(.system(.subheadline, design: .serif))
                } else if !entry.wroteToday, let prompt = entry.prompt {
                    Text("Today's prompt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(prompt)
                        .font(.system(.subheadline, design: .serif))
                        .lineLimit(4)
                } else {
                    Text(entry.wroteToday ? "Nice work. See you tomorrow." : "How was your day?")
                        .font(.system(.subheadline, design: .serif))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Image(systemName: entry.wroteToday ? "checkmark" : "flame.fill")
                .font(.caption)
            Text(entry.streak.formatted())
                .font(.system(.title3, design: .serif, weight: .semibold))
        }
        .widgetAccentable()
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Dabble Me")
                .font(.headline)
                .widgetAccentable()
            Text(streakText)
            Text(entry.wroteToday ? "Written today" : "Tap to write today")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Color {
    static let sage = Color(red: 0x5C / 255, green: 0x66 / 255, blue: 0x54 / 255)
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x16 / 255, green: 0x17 / 255, blue: 0x14 / 255, alpha: 1)
            : UIColor(red: 0xF9 / 255, green: 0xF7 / 255, blue: 0xF3 / 255, alpha: 1)
    })
}
