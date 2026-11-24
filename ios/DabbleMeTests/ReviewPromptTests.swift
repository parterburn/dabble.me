import Foundation
import Testing
@testable import DabbleMe

struct ReviewPromptTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ReviewPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }()

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: start)!
    }

    @Test func waitsForThreeDifferentWritingDays() {
        let defaults = freshDefaults()
        ReviewPrompt.recordNewEntry(now: day(0), calendar: calendar, defaults: defaults)
        // Several entries in one sitting are still one day.
        ReviewPrompt.recordNewEntry(now: day(0, hour: 13), calendar: calendar, defaults: defaults)
        ReviewPrompt.recordNewEntry(now: day(0, hour: 20), calendar: calendar, defaults: defaults)
        #expect(ReviewPrompt.decision(version: "1.2", now: day(0), defaults: defaults) == .tooFewDays(1))
        ReviewPrompt.recordNewEntry(now: day(3), calendar: calendar, defaults: defaults)
        #expect(ReviewPrompt.decision(version: "1.2", now: day(3), defaults: defaults) == .tooFewDays(2))
        ReviewPrompt.recordNewEntry(now: day(4), calendar: calendar, defaults: defaults)
        #expect(ReviewPrompt.decision(version: "1.2", now: day(4), defaults: defaults) == .ask)
    }

    @Test func asksOncePerVersionAndNotTooSoon() {
        let defaults = freshDefaults()
        for offset in 0..<3 { ReviewPrompt.recordNewEntry(now: day(offset), calendar: calendar, defaults: defaults) }
        ReviewPrompt.markAsked(version: "1.2", now: day(2), defaults: defaults)
        #expect(ReviewPrompt.decision(version: "1.2", now: day(200), defaults: defaults) == .askedThisVersion)
        #expect(ReviewPrompt.decision(version: "1.3", now: day(32), defaults: defaults) == .askedRecently(daysAgo: 30))
        #expect(ReviewPrompt.decision(version: "1.3", now: day(2 + ReviewPrompt.minimumDaysBetweenAsks), defaults: defaults) == .ask)
        // TestFlight: each build can be checked, with no wait between them.
        #expect(ReviewPrompt.decision(version: "1.3", ignoresGap: true, now: day(3), defaults: defaults) == .ask)
    }

    @Test func keepsOnlyRecentDays() {
        let defaults = freshDefaults()
        for offset in 0..<25 { ReviewPrompt.recordNewEntry(now: day(offset), calendar: calendar, defaults: defaults) }
        let days = defaults.stringArray(forKey: ReviewPrompt.writingDaysKey) ?? []
        #expect(days.count == ReviewPrompt.keptDays)
        #expect(days.last == "2026-11-25")
    }

    @Test func testFlightVersionIncludesTheBuild() {
        let version = ReviewPrompt.version(inTestFlight: true)
        #expect(version.hasPrefix(ReviewPrompt.version(inTestFlight: false) + " ("))
    }
}
