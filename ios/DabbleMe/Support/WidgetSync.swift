import Foundation
import WidgetKit

/// Keeps the home-screen widget's snapshot (streak, written today, optional memory count and
/// today's prompt) in step with the app. No entry text goes to the widget. The prompt is the
/// personal one Apple Intelligence wrote for today when there is one, unless the app is locked
/// with Face ID (it's drawn from the journal, and widgets show without unlocking).
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
            prompt: personalPrompt(for: today.date, model: model) ?? today.prompt
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

    static func setShowsMemories(_ shows: Bool) {
        WidgetSnapshot.defaults?.set(shows, forKey: WidgetSnapshot.showMemoriesKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        WidgetSnapshot.clear()
        WidgetSnapshot.defaults?.removeObject(forKey: WidgetSnapshot.showMemoriesKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
