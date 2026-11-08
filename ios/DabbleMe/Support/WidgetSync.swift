import Foundation
import WidgetKit

/// Keeps the home-screen widget's snapshot (streak, written today, optional memory count and
/// today's prompt) in step with the app. No entry text goes to the widget.
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
            prompt: today.prompt
        )
        guard snapshot != WidgetSnapshot.load() else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
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
