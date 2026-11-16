import Foundation
import UIKit
import WidgetKit

/// Keeps the home-screen widget's snapshot (the year's entry count, written today, today's prompt
/// and the start of today's entry and of one to look back on) in step with the app. The prompt is the
/// personal one Apple Intelligence wrote for today when there is one. Settings → Home Screen
/// Widget decides what goes on it; the Face ID lock doesn't (it guards the app, and the person
/// chose what the widget shows).
@MainActor
enum WidgetSync {
    static func update(from model: AppModel) {
        guard model.isSignedIn, let today = model.today else { return }
        let memories = today.onThisDay
        // Both entries a widget might show, whatever's chosen now: each widget can choose for
        // itself (Edit Widget), and shouldn't have to wait for the app to be opened again.
        let written = shownEntry(today, content: .promptEntry, model: model)
        let lookBack = shownEntry(today, content: .memoryEntry, model: model)
        let saved = WidgetSnapshot.load()
        var snapshot = WidgetSnapshot(
            day: today.date,
            wroteToday: today.entry != nil,
            yearCount: model.entriesThisYear ?? 0,
            memories: memories.count,
            memoriesFirstYear: memories.compactMap { $0.day.flatMap { Int($0.year) } }.min(),
            memoryNote: memoryNote(today),
            prompt: personalPrompt(for: today.date, model: model) ?? today.prompt,
            todayEntry: written.map { .init(title: $0.title, text: $0.text, id: $0.id, photo: photo(for: $0.entry, model: model)) },
            rewindEntry: lookBack.map { .init(title: $0.title, text: $0.text, id: $0.id, photo: photo(for: $0.entry, model: model)) },
            // Today and the days ahead as last worked out, until they're worked out again (below).
            upcoming: saved?.upcoming.flatMap { days in
                let current = days.filter { $0.day >= today.date }
                return current.isEmpty ? nil : current
            },
            // (A plan worked out on an earlier day still holds for the days it reached.)
            plannedThrough: saved?.plannedThrough.flatMap { $0 >= today.date ? $0 : nil }
        )
        snapshot.writtenDays = writtenDays(saved?.writtenDays, today: today)
        if snapshot != saved {
            snapshot.save()
            removePhotos(except: snapshot.photoNames)
            WidgetCenter.shared.reloadAllTimelines()
        }
        Task {
            await updateWrittenDays(from: model)
            await updateUpcoming(from: model)
        }
    }

    /// The days written lately as last fetched, with today's put right by what Today says now
    /// (an entry written or deleted since).
    private static func writtenDays(_ saved: [String]?, today: TodaySummary) -> [String]? {
        guard var days = saved else { return nil }
        days.removeAll { $0 == today.date }
        if today.entry != nil { days.append(today.date) }
        return days.sorted()
    }

    /// What the last fetch of the written days was for (fetched again when the journal's
    /// changed), and the one under way: the widget's updated from several places at once.
    private static var writtenDaysKey: String?
    private static var writtenDaysFetching: String?

    /// The past few weeks' written days, for the widget's row of the last five (kept a while
    /// ahead: the row moves on a day at midnight without the app).
    private static func updateWrittenDays(from model: AppModel) async {
        guard let today = model.today, let account = model.me?.id else { return }
        let key = "\(account)|\(today.date)|\(model.me?.entryCount ?? 0)|\(today.entry?.id ?? 0)"
        guard key != writtenDaysFetching,
              key != writtenDaysKey || WidgetSnapshot.load()?.writtenDays == nil || model.recentWrittenDays == nil,
              let day = today.day, let from = Calendar.current.date(byAdding: .day, value: -21, to: day.localDate) else { return }
        let earliest = WidgetSnapshot.iso(from)
        writtenDaysFetching = key
        defer { if writtenDaysFetching == key { writtenDaysFetching = nil } }
        // Three weeks' worth, not the whole journal's.
        guard let days = try? await model.entryDays(since: earliest) else { return }
        let recent = days.filter { $0 >= earliest }.sorted()
        guard model.isSignedIn, model.me?.id == account, model.today?.date == today.date else { return }
        // For the app's own rows of them too (Today's corner, Stats).
        model.recentWrittenDays = recent
        guard var snapshot = WidgetSnapshot.load(), snapshot.day == today.date else { return }
        writtenDaysKey = key
        guard snapshot.writtenDays != recent else { return }
        snapshot.writtenDays = recent
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - The days ahead

    /// How many later days the widget is given a look back for, and how many of those with
    /// their photo (previews on).
    private static let daysAhead = 14
    private static let photosAhead = 7

    /// Rewind for today and the coming days (the entries the daily reminder would show: On This
    /// Day's first, or else the day's Rewind), saved with the snapshot. Without the days ahead
    /// the widget had nothing to look back on from midnight until the app was next opened. And
    /// with today's from the same place, one rule holds every day: the filters in Settings →
    /// Reminders → Past Entries (never the words left out there).
    private static func updateUpcoming(from model: AppModel) async {
        guard let today = model.today?.date, let account = model.me?.id,
              let plan = await ReminderScheduler.shared.lookBacks(for: model) else { return }
        // Still this account and day (asked again after each wait: someone can sign out, and
        // into another journal, while a photo's on its way).
        func isCurrent() -> Bool { model.isSignedIn && model.me?.id == account && model.today?.date == today }
        guard isCurrent() else { return }
        var days: [WidgetSnapshot.Day] = []
        for memory in plan.days where memory.date >= today {
            guard days.count < daysAhead, isCurrent() else { break }
            days.append(await lookBack(memory, withPhoto: days.count < photosAhead))
        }
        // The plan runs from today for as many days as were asked for.
        let through = JournalDay(today).flatMap { Calendar.current.date(byAdding: .day, value: daysAhead - 1, to: $0.localDate) }
            .map { JournalDay(localDate: $0).iso } ?? today
        guard isCurrent(), var snapshot = WidgetSnapshot.load(), snapshot.day == today,
              snapshot.upcoming ?? [] != days || snapshot.plannedThrough != through else { return }
        snapshot.upcoming = days.isEmpty ? nil : days
        snapshot.plannedThrough = through
        snapshot.save()
        removePhotos(except: snapshot.photoNames)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// One later day, as a widget will show it: a count or a note, and (for one with previews on)
    /// the entry's start and its photo's small copy.
    private static func lookBack(_ memory: ReminderPlan.Day, withPhoto: Bool) async -> WidgetSnapshot.Day {
        let entryDay = JournalDay(memory.entry.date), day = JournalDay(memory.date)
        let ago = entryDay.flatMap { entry in day.map { entry.relative(to: $0) } }
        var result = WidgetSnapshot.Day(day: memory.date)
        if memory.isOnThisDay {
            result.memories = memory.count
        } else if let ago {
            result.memoryNote = "You have a memory from \(ago.prefix(1).lowercased() + ago.dropFirst())."
        }
        if memory.isOnThisDay, let entryDay, let day, let years = Int(day.year).flatMap({ now in Int(entryDay.year).map { now - $0 } }) {
            result.entryTitle = "\(years == 1 ? "1 year ago" : "\(years) years ago") · \(entryDay.year)"
        } else {
            result.entryTitle = ago ?? "Rewind"
        }
        result.entryText = String(memory.entry.excerpt.prefix(400))
        result.entryID = memory.entry.id
        if withPhoto, !EntrySummary.isUploadingPlaceholder(memory.entry.imageUrl),
           let url = EntrySummary.thumbnailURL(memory.entry.imageUrl, width: 700) {
            let name = "entry-\(memory.entry.id).jpg"
            if let file = WidgetSnapshot.photoURL(named: name) {
                let saved = FileManager.default.fileExists(atPath: file.path)
                if saved { result.entryPhoto = name } else if await download(url, to: file) { result.entryPhoto = name }
            }
        }
        return result
    }

    private static func personalPrompt(for day: String, model: AppModel) -> String? {
        guard JournalIntelligence.isEnabled(for: model.me),
              UserDefaults.standard.string(forKey: "ai.prompt.day") == day,
              let text = UserDefaults.standard.string(forKey: "ai.prompt.text"), !text.isEmpty else { return nil }
        return text
    }

    /// The entry whose start shows on the widget, when previews are on: for Rewind, On This Day's
    /// first memory or else the past entry Today shows as its Rewind; for A Prompt for You, today's
    /// own entry once it's written.
    private static func shownEntry(_ today: TodaySummary, content: WidgetContent, model: AppModel) -> (title: String, text: String, id: Int, entry: EntrySummary)? {
        let title: String
        let entry: EntrySummary
        switch content {
        case .prompt, .memoryCount:
            return nil
        case .promptEntry:
            guard let written = today.entry else { return nil }
            entry = written.summary
            title = WidgetEntry.todayTitle
        case .memoryEntry:
            if let memory = today.onThisDay.first {
                entry = memory
                let years = memory.yearsAgo.map { $0 == 1 ? "1 year ago" : "\($0) years ago" }
                title = [years, memory.day?.year].compactMap { $0 }.joined(separator: " · ")
            } else if let rewind = today.throwback, let day = rewind.day, let now = today.day {
                entry = rewind
                title = day.relative(to: now) // "2 years + 3 months ago": the icon says it's a look back
            } else {
                return nil
            }
        }
        let text = entry.excerpt.isEmpty ? "" : String(entry.excerpt.prefix(400))
        return (title, text, entry.id, entry)
    }

    /// Rewind without previews, with nothing on this day in past years: "You have a memory from
    /// 36 days ago." (the past entry Today shows as its Rewind).
    static func memoryNote(_ today: TodaySummary) -> String? {
        guard today.onThisDay.isEmpty, let day = today.throwback?.day, let now = today.day else { return nil }
        let ago = day.relative(to: now)
        return "You have a memory from \(ago.prefix(1).lowercased() + ago.dropFirst())."
    }

    // MARK: - The entry's photo

    /// The file name of an entry's photo once its small copy is saved; until then nil, and the
    /// copy is fetched (then the widget updates again). `fetches` is off for the settings
    /// preview, which fetches its own.
    private static func photo(for entry: EntrySummary?, model: AppModel, fetches: Bool = true) -> String? {
        // (Not while it's uploading: the stand-in picture isn't one to keep.)
        guard let entry, !entry.imageProcessing, !EntrySummary.isUploadingPlaceholder(entry.imageUrl),
              let url = entry.thumbnailURL(width: 700) else { return nil }
        let name = "entry-\(entry.id).jpg"
        guard let file = WidgetSnapshot.photoURL(named: name) else { return nil }
        if FileManager.default.fileExists(atPath: file.path) { return name }
        guard fetches else { return nil }
        Task {
            guard await download(url, to: file) else { return }
            update(from: model)
        }
        return nil
    }

    /// Settings → Home Screen Widget: fetches the photo the preview would show (if any), so the
    /// preview can redraw with it.
    static func preparePreviewPhoto(for content: WidgetContent, model: AppModel) async {
        guard let today = model.today, let entry = shownEntry(today, content: content, model: model)?.entry,
              !entry.imageProcessing, !EntrySummary.isUploadingPlaceholder(entry.imageUrl),
              let url = entry.thumbnailURL(width: 700), let file = WidgetSnapshot.photoURL(named: "entry-\(entry.id).jpg"),
              !FileManager.default.fileExists(atPath: file.path) else { return }
        _ = await download(url, to: file)
    }

    /// Downloads a photo copy once: a second caller while it's under way waits for the same one
    /// (so the settings preview only redraws once the file is there).
    private static func download(_ url: URL, to file: URL) async -> Bool {
        let name = file.lastPathComponent
        if let running = downloads[name] { return await running.value }
        let task = Task<Bool, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let jpeg = await Task.detached(operation: { smallJPEG(data) }).value else { return false }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            return (try? jpeg.write(to: file, options: .atomic)) != nil
        }
        downloads[name] = task
        let saved = await task.value
        downloads[name] = nil
        return saved
    }

    private static var downloads: [String: Task<Bool, Never>] = [:]

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

    /// Deletes the widget's other photo copies: only inside `WidgetSnapshot.photoFolder`, never the
    /// rest of the App Group (its shared settings live there too).
    static func removePhotos(except keep: Set<String>) {
        guard let folder = WidgetSnapshot.photoFolder,
              let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for file in files where !keep.contains(file) {
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
    }

    static func setContent(_ content: WidgetContent, model: AppModel) {
        WidgetSnapshot.content = content
        model.widgetChoiceChanges += 1
        update(from: model)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// What the widget would show with `content`, from today's data (Settings → Home Screen
    /// Widget's preview). The same rules as the widget, Face ID included.
    static func previewEntry(for content: WidgetContent, model: AppModel) -> WidgetEntry {
        guard let today = model.today else { return .placeholder }
        // Rewind as the widget has it: the day's planned look back.
        if content.source == .rewind, let saved = WidgetSnapshot.load(), saved.day == today.date, saved.rewind(on: .now).known {
            let day = saved.upcoming?.first { $0.day == today.date }
            let showsEntry = content == .memoryEntry
            return WidgetEntry(date: .now, signedIn: true, wroteToday: today.entry != nil,
                               yearCount: model.entriesThisYear ?? 0, lastFiveDays: WidgetSnapshot.load()?.lastFiveDays(on: .now), memories: day?.memories,
                               prompt: personalPrompt(for: today.date, model: model) ?? today.prompt,
                               memoryNote: content == .memoryCount ? day?.memoryNote : nil,
                               entryTitle: showsEntry ? day?.entryTitle : nil, entryText: showsEntry ? day?.entryText : nil,
                               entryID: showsEntry ? day?.entryID : nil,
                               photo: showsEntry ? day?.entryPhoto.flatMap(WidgetSnapshot.photoURL(named:)).flatMap { UIImage(contentsOfFile: $0.path) } : nil)
        }
        let shown = shownEntry(today, content: content, model: model)
        return WidgetEntry(date: .now, signedIn: true, wroteToday: today.entry != nil,
                           yearCount: model.entriesThisYear ?? 0, lastFiveDays: WidgetSnapshot.load()?.lastFiveDays(on: .now),
                           memories: content.source == .rewind && !today.onThisDay.isEmpty ? today.onThisDay.count : nil,
                           prompt: personalPrompt(for: today.date, model: model) ?? today.prompt,
                           memoryNote: content == .memoryCount ? memoryNote(today) : nil,
                           entryTitle: shown?.title, entryText: shown?.text, entryID: shown?.id,
                           photo: photo(for: shown?.entry, model: model, fetches: false)
                               .flatMap(WidgetSnapshot.photoURL(named:)).flatMap { UIImage(contentsOfFile: $0.path) })
    }

    static func clear() {
        WidgetSnapshot.clear()
        WidgetSnapshot.defaults?.removeObject(forKey: WidgetSnapshot.showMemoriesKey)
        WidgetSnapshot.defaults?.removeObject(forKey: WidgetSnapshot.contentKey)
        removePhotos(except: [])
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private extension WidgetSnapshot {
    /// Every photo copy the snapshot points at: its own day's and the days' ahead.
    var photoNames: Set<String> {
        Set(([todayEntry?.photo, rewindEntry?.photo] + (upcoming ?? []).map(\.entryPhoto)).compactMap { $0 })
    }
}
