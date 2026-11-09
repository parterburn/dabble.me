import Foundation
import WidgetKit

/// Keeps the home-screen widget's snapshot (streak, written today, today's prompt and, only with
/// "Show Entries in Widget" on, an entry to look back on) in step with the app. The prompt is the
/// personal one Apple Intelligence wrote for today when there is one. Neither the personal prompt
/// nor any entry text goes to the widget while the app is locked with Face ID (widgets show
/// without unlocking).
@MainActor
enum WidgetSync {
    static func update(from model: AppModel) {
        guard model.isSignedIn, let today = model.today else { return }
        let memories = today.onThisDay
        let snapshot = WidgetSnapshot(
            day: today.date,
            wroteToday: today.entry != nil,
            streak: today.currentStreak ?? 0,
            memories: memories.count,
            memoriesFirstYear: memories.compactMap { $0.day.flatMap { Int($0.year) } }.min(),
            prompt: personalPrompt(for: today.date, model: model) ?? today.prompt,
            entryTitle: shownEntry(today, model: model)?.title,
            entryText: shownEntry(today, model: model)?.text
        )
        guard snapshot != WidgetSnapshot.load() else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func personalPrompt(for day: String, model: AppModel) -> String? {
        guard JournalIntelligence.isEnabled(for: model.me), !model.lock.isEnabled,
              UserDefaults.standard.string(forKey: "ai.prompt.day") == day,
              let text = UserDefaults.standard.string(forKey: "ai.prompt.text"), !text.isEmpty else { return nil }
        return text
    }

    /// On This Day's first memory, or else the throwback, when the person has asked for entries on
    /// the widget and the app isn't locked.
    private static func shownEntry(_ today: TodaySummary, model: AppModel) -> (title: String, text: String)? {
        guard WidgetSnapshot.showsMemories, !model.lock.isEnabled else { return nil }
        let title: String
        let entry: EntrySummary
        if let memory = today.onThisDay.first {
            entry = memory
            let years = memory.yearsAgo.map { $0 == 1 ? "1 year ago" : "\($0) years ago" }
            title = [years, memory.day?.year].compactMap { $0 }.joined(separator: " · ")
        } else if let throwback = today.throwback, let day = throwback.day, let now = today.day {
            entry = throwback
            title = "Throwback · \(day.relative(to: now))"
        } else {
            return nil
        }
        let text = entry.excerpt.isEmpty ? "📷 Photo" : String(entry.excerpt.prefix(240))
        return (title, text)
    }

    static func setShowsMemories(_ shows: Bool, model: AppModel) {
        WidgetSnapshot.defaults?.set(shows, forKey: WidgetSnapshot.showMemoriesKey)
        update(from: model)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        WidgetSnapshot.clear()
        WidgetSnapshot.defaults?.removeObject(forKey: WidgetSnapshot.showMemoriesKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
