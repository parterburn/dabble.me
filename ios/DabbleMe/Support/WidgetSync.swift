import Foundation
import UIKit
import WidgetKit

/// Keeps the home-screen widget's snapshot (streak, written today, today's prompt and, only with
/// "On This Day Entry" chosen, an entry to look back on) in step with the app. The prompt is the
/// personal one Apple Intelligence wrote for today when there is one. Settings → Home Screen
/// Widget decides what goes on it; the Face ID lock doesn't (it guards the app, and the person
/// chose what the widget shows).
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
            entryText: shownEntry(today, content: WidgetSnapshot.content, model: model)?.text,
            entryID: shownEntry(today, content: WidgetSnapshot.content, model: model)?.id,
            entryPhoto: photo(for: shownEntry(today, content: WidgetSnapshot.content, model: model)?.entry, model: model)
        )
        guard snapshot != WidgetSnapshot.load() else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func personalPrompt(for day: String, model: AppModel) -> String? {
        guard JournalIntelligence.isEnabled(for: model.me),
              UserDefaults.standard.string(forKey: "ai.prompt.day") == day,
              let text = UserDefaults.standard.string(forKey: "ai.prompt.text"), !text.isEmpty else { return nil }
        return text
    }

    /// On This Day's first memory, or else the throwback, when the person has asked for entries on
    /// the widget.
    private static func shownEntry(_ today: TodaySummary, content: WidgetContent, model: AppModel) -> (title: String, text: String, id: Int, entry: EntrySummary)? {
        guard content == .memoryEntry else { return nil }
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
        let text = entry.excerpt.isEmpty ? "" : String(entry.excerpt.prefix(400))
        return (title, text, entry.id, entry)
    }

    // MARK: - The entry's photo

    /// The file name of the shown entry's photo once its small copy is saved; until then nil, and
    /// the copy is fetched (then the widget updates again). Other entries' copies are removed.
    /// `cleansUp` is for the widget's own updates; the settings preview leaves the files alone.
    private static func photo(for entry: EntrySummary?, model: AppModel, cleansUp: Bool = true) -> String? {
        guard let entry, let url = entry.thumbnailURL(width: 700) else {
            if cleansUp { removePhotos(except: nil) }
            return nil
        }
        let name = "entry-\(entry.id).jpg"
        guard let file = WidgetSnapshot.photoURL(named: name) else { return nil }
        if FileManager.default.fileExists(atPath: file.path) { return name }
        Task {
            guard await download(url, to: file) else { return }
            if cleansUp { removePhotos(except: name) }
            update(from: model)
        }
        return nil
    }

    /// Settings → Home Screen Widget: fetches the photo the preview would show (if any), so the
    /// preview can redraw with it.
    static func preparePreviewPhoto(for content: WidgetContent, model: AppModel) async {
        guard let today = model.today, let entry = shownEntry(today, content: content, model: model)?.entry,
              let url = entry.thumbnailURL(width: 700), let file = WidgetSnapshot.photoURL(named: "entry-\(entry.id).jpg"),
              !FileManager.default.fileExists(atPath: file.path) else { return }
        _ = await download(url, to: file)
    }

    private static func download(_ url: URL, to file: URL) async -> Bool {
        let name = file.lastPathComponent
        guard !downloading.contains(name) else { return false }
        downloading.insert(name)
        defer { downloading.remove(name) }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let jpeg = await Task.detached(operation: { smallJPEG(data) }).value else { return false }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? jpeg.write(to: file, options: .atomic)) != nil
    }

    private static var downloading: Set<String> = []

    /// At most 700 points wide: widgets have little memory, and that's sharp at widget size.
    nonisolated private static func smallJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, 700 / max(image.size.width, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.8)
    }

    private static func removePhotos(except keep: String?) {
        guard let folder = WidgetSnapshot.photoURL(named: "")?.deletingLastPathComponent(),
              let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for file in files where file != keep {
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
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
                           entryTitle: shown?.title, entryText: shown?.text, entryID: shown?.id,
                           photo: photo(for: shown?.entry, model: model, cleansUp: false)
                               .flatMap(WidgetSnapshot.photoURL(named:)).flatMap { UIImage(contentsOfFile: $0.path) })
    }

    static func clear() {
        WidgetSnapshot.clear()
        WidgetSnapshot.defaults?.removeObject(forKey: WidgetSnapshot.showMemoriesKey)
        WidgetSnapshot.defaults?.removeObject(forKey: WidgetSnapshot.contentKey)
        removePhotos(except: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
