import SwiftUI
import UIKit
import WidgetKit

struct WidgetEntry: TimelineEntry {
    let date: Date
    let signedIn: Bool
    let wroteToday: Bool
    /// Entries written so far in `date`'s year.
    let yearCount: Int
    let memories: Int?
    let prompt: String?
    /// An entry to look back on (only with "On This Day Entry" chosen in the app).
    var entryTitle: String? = nil
    var entryText: String? = nil
    var entryID: Int? = nil
    /// The entry's photo, when it has one (a small copy from the App Group).
    var photo: UIImage? = nil

    static let placeholder = WidgetEntry(date: .now, signedIn: true, wroteToday: false, yearCount: 36, memories: nil,
                                         prompt: "What made you smile today?")
}

/// The widget's content for a family. In `Shared` so the app's widget settings can preview it.
struct TodayWidgetContent: View {
    let entry: WidgetEntry
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Text(entry.wroteToday ? "✓ \(countText)" : "Write today · \(countText)")
        case .systemMedium: medium
        default: small
        }
    }

    private var year: String { entry.date.formatted(.dateTime.year()) }

    /// "36 entries in 2026"
    private var countText: String {
        "\(entry.yearCount.formatted()) \(entry.yearCount == 1 ? "entry" : "entries") in \(year)"
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            wordmark
            Spacer(minLength: 0)
            if entry.signedIn {
                Text(entry.yearCount.formatted())
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .contentTransition(.numericText())
                Text("\(entry.yearCount == 1 ? "entry" : "entries") in \(year)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                status
            } else {
                Text("Sign in to see your journal.")
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

    /// Two halves, each its own link: the count side writes today's entry (or opens Today once
    /// it's written), and an entry shown on the right opens that entry to read.
    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            Link(destination: entry.wroteToday ? WidgetSnapshot.todayURL : WidgetSnapshot.writeURL) {
                small
            }
            .frame(maxWidth: 130)
            mediumDetail
        }
    }

    @ViewBuilder
    private var mediumDetail: some View {
        if let id = entry.entryID, entry.entryText != nil {
            Link(destination: WidgetSnapshot.entryURL(id)) { mediumDetailContent }
        } else {
            mediumDetailContent
        }
    }

    /// "Dabble me." in the logo's colors: Instrument Serif, near-black with an olive period (white
    /// with a lighter sage period in dark mode).
    private var wordmark: some View {
        (Text("Dabble me").foregroundStyle(Color.logoInk) + Text(".").foregroundStyle(Color.logoPeriod))
            .font(.custom("InstrumentSerif-Regular", size: 23))
            .accessibilityLabel("Dabble Me")
    }

    /// An entry with a photo: the photo fills the side, with a few words of the entry over it
    /// (a picture says the rest).
    @ViewBuilder
    private var mediumDetailContent: some View {
        if let photo = entry.photo, let title = entry.entryTitle {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .overlay {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    if let text = entry.entryText, !text.isEmpty {
                        Text(text)
                            .font(.system(.footnote, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                }
                .padding(10)
            }
            .clipShape(.rect(cornerRadius: 14))
        } else {
            mediumDetailText
        }
    }

    private var mediumDetailText: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let title = entry.entryTitle, let text = entry.entryText {
                    Label(title, systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(text.isEmpty ? "📷 Photo" : text)
                        .font(.system(.subheadline, design: .serif))
                        .lineLimit(5)
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
            Image(systemName: entry.wroteToday ? "checkmark" : "square.and.pencil")
                .font(.caption)
            Text(entry.yearCount.formatted())
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
            Text(countText)
            Text(entry.wroteToday ? "Written today" : "Tap to write today")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Color {
    /// The dabble.me logo's colors.
    static let logoInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
    })
    static let logoPeriod = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xA9 / 255, green: 0xAD / 255, blue: 0x9B / 255, alpha: 1)
            : UIColor(red: 0x5C / 255, green: 0x66 / 255, blue: 0x54 / 255, alpha: 1)
    })
    static let sage = Color(red: 0x5C / 255, green: 0x66 / 255, blue: 0x54 / 255)
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x16 / 255, green: 0x17 / 255, blue: 0x14 / 255, alpha: 1)
            : UIColor(red: 0xF9 / 255, green: 0xF7 / 255, blue: 0xF3 / 255, alpha: 1)
    })
}
