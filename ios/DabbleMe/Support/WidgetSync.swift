import Foundation
import WidgetKit

/// Keeps the home-screen widget's snapshot (streak, written today, today's prompt and, only with
/// "On This Day Entry" chosen, an entry to look back on) in step with the app. The prompt is the
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
            entryTitle: shownEntry(today, content: WidgetSnapshot.content, model: model)?.title,
            entryText: shownEntry(today, content: WidgetSnapshot.content, model: model)?.text
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
    private static func shownEntry(_ today: TodaySummary, content: WidgetContent, model: AppModel) -> (title: String, text: String)? {
        guard content == .memoryEntry, !model.lock.isEnabled else { return nil }
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

    static func setContent(_ content: WidgetContent, model: AppModel) {
        WidgetSnapshot.content = content
        update(from: model)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// What the widget would show with `content`, from today's data (Settings → Home Screen
    /// Widget's preview). The same rules as the widget, Face ID included.
    static func previewEntry(for content: WidgetContent, model: AppModel) -> WidgetEntry {
        guard let today = model.today else { return .placeholder }
        let shown = shownEntry(today, content: content, model: model)
        return WidgetEntry(date: .now, signedIn: true, wroteToday: today.entry != nil,
                           streak: today.currentStreak ?? 0,
                           memories: content != .prompt && !today.onThisDay.isEmpty ? today.onThisDay.count : nil,
                           prompt: personalPrompt(for: today.date, model: model) ?? today.prompt,
                           entryTitle: shown?.title, entryText: shown?.text)
    }

    static func clear() {
        WidgetSnapshot.clear()
        WidgetSnapshot.defaults?.removeObject(forKey: WidgetSnapshot.showMemoriesKey)
        WidgetSnapshot.defaults?.removeObject(forKey: WidgetSnapshot.contentKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
