import Foundation
import ImageIO
import UIKit
import Testing
import UniformTypeIdentifiers
@testable import DabbleMe

struct PKCETests {
    @Test func s256ChallengeMatchesKnownVector() {
        let pkce = PKCE(verifier: "M25iVXpKU3puUjFaYWg3T1NDTDQtcW1ROUY5YXlwalNoc0hhakxifmZHag")
        #expect(pkce.challenge == "qjrzSW9gMiUgpUvqgEPE4_-8swvyCtfOVvg55o5S_es")
    }

    @Test func generatedVerifierIsURLSafeAndLongEnough() {
        let verifier = PKCE().verifier
        #expect(verifier.count >= 43) // RFC 7636 minimum
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test func authorizeURLCarriesTheAppClient() throws {
        let url = OAuthEndpoints.authorizeURL(pkce: PKCE(), state: "abc")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.path() == "/oauth/authorize")
        #expect(query["client_id"] == "dabble-me-ios")
        #expect(query["scope"] == "app:journal")
        #expect(query["redirect_uri"] == "me.dabble.app:/oauth/callback")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["state"] == "abc")
    }
}

struct JournalDayTests {
    @Test func formatsWithoutShiftingTheDay() throws {
        let day = try #require(JournalDay("2025-03-04"))
        #expect(day.dayNumber == "4")
        #expect(day.monthKey == "2025-03")
        #expect(day.year == "2025")
    }

    @Test func roundTripsThroughTheLocalCalendar() throws {
        for timeZone in ["Pacific/Kiritimati", "Pacific/Pago_Pago", "America/Denver"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: timeZone))
            let local = try #require(calendar.date(from: DateComponents(year: 2024, month: 12, day: 31, hour: 23)))
            #expect(JournalDay(localDate: local, calendar: calendar).iso == "2024-12-31")
        }
    }

    @Test func rejectsGarbage() {
        #expect(JournalDay("not-a-date") == nil)
    }
}

@MainActor
struct PromptGroundingTests {
    @Test func namesMustComeFromTheEntry() {
        let draft = "Boys had basketball practice. Leo hit three in a row and Coach Dana laughed."
        #expect(JournalIntelligence.namesAreGrounded("What did it feel like when Leo hit three in a row?", in: draft))
        #expect(JournalIntelligence.namesAreGrounded("Why did Coach Dana's laugh stay with you?", in: draft))
        #expect(!JournalIntelligence.namesAreGrounded("What did Sam think of the practice?", in: draft), "Sam isn't in the entry")
        #expect(!JournalIntelligence.namesAreGrounded("How did the game in Denver go?", in: draft), "Nor is Denver")
        #expect(JournalIntelligence.namesAreGrounded("What made I so happy?", in: draft), "\"I\" isn't a name")
    }

    /// A question may reword what's written, but not add a scene to it.
    @Test func questionsStickToWhatIsWritten() {
        let hike = "Went #hiking with Sam."
        #expect(JournalIntelligence.wordsAreGrounded("What do you want to remember about hiking with Sam?", in: hike))
        #expect(JournalIntelligence.wordsAreGrounded("What did going hiking with Sam feel like for you?", in: hike))
        #expect(!JournalIntelligence.wordsAreGrounded("What was it like when Sam walked ahead, alone?", in: hike))
        #expect(!JournalIntelligence.wordsAreGrounded("What did it feel like when Sam sang badly during the descent?", in: hike))
        #expect(!JournalIntelligence.wordsAreGrounded("What did Sam’s voice sound like when you were walking?", in: hike))
        let tooth = "Leo lost his first tooth tonight! He was so proud and a little scared of the blood."
        #expect(JournalIntelligence.wordsAreGrounded("What do you want to remember about Leo’s pride when he lost his first tooth?", in: tooth))
        #expect(JournalIntelligence.wordsAreGrounded("How did it feel when Leo was scared of the blood?", in: tooth))
    }
}

@MainActor
struct HashtagMatchingTests {
    /// The writer's tags that are words in the entry come first in the composer's row, without a model.
    @Test func tagsMatchWholeWordsWhateverTheCase() {
        let tags = ["travel", "Hiking", "sam", "work", "hiking", "hike"]
        #expect(JournalIntelligence.tags(tags, matchingWordsIn: "Went hiking with Sam. No workdays!") == ["Hiking", "sam"])
        #expect(JournalIntelligence.tags(tags, matchingWordsIn: "").isEmpty)
    }
}

@MainActor
struct StatsOverviewTests {
    @Test func wordsCompareToABookOnceThereAreEnough() {
        #expect(JournalIntelligence.bookComparison(words: 5_000) == nil)
        #expect(JournalIntelligence.bookComparison(words: 30_000) == "about 64% of the length of The Great Gatsby")
        #expect(JournalIntelligence.bookComparison(words: 50_000) == "about as long as The Great Gatsby")
        #expect(JournalIntelligence.bookComparison(words: 100_000) == "about as long as The Hobbit")
        #expect(JournalIntelligence.bookComparison(words: 1_200_000) == "about 2 times the length of War and Peace")
    }

    /// The overview isn't given a name, so one in its reply was made up.
    @Test func anOverviewWithANameIsCaught() {
        let facts = "Writing since November 2023. 18 entries in all, 15 of them in 2026. Writes most often on Mondays. Busiest month of the last 12: October (6 entries)."
        #expect(!JournalIntelligence.overviewUsesAName("You've written 18 entries since November 2023. Mondays are your day, and October was your busiest month.", facts: facts))
        #expect(JournalIntelligence.overviewUsesAName("Sam, you've written 18 entries since November 2023.", facts: facts))
        #expect(JournalIntelligence.overviewUsesAName("Great work, Alex! You write most often on Mondays.", facts: facts))
        #expect(JournalIntelligence.overviewUsesAName("Hi Jordan. You've written 18 entries.", facts: facts))
    }
}

@MainActor
struct WebLinksTests {
    /// dabble.me pages open in the app; other sites, and the link to subscribe, go to the browser.
    @Test func onlyOurPagesOpenInTheApp() {
        #expect(WebLinks.opensInApp(URL(string: "https://dabble.me/support")!))
        #expect(WebLinks.opensInApp(URL(string: "https://dabble.me/security")!))
        #expect(!WebLinks.opensInApp(URL(string: "https://dabble.me/subscribe")!))
        #expect(!WebLinks.opensInApp(URL(string: "https://open.spotify.com/track/1")!))
        #expect(!WebLinks.opensInApp(URL(string: "mailto:hello@dabble.me")!))
    }
}

struct WidgetContentTests {
    @Test func twoChoicesAndASwitch() {
        #expect(WidgetContent(source: .prompt, showsPreviews: false) == .prompt)
        #expect(WidgetContent(source: .prompt, showsPreviews: true) == .promptEntry)
        #expect(WidgetContent(source: .rewind, showsPreviews: false) == .memoryCount)
        #expect(WidgetContent(source: .rewind, showsPreviews: true) == .memoryEntry)
        for content in WidgetContent.allCases {
            #expect(WidgetContent(source: content.source, showsPreviews: content.showsPreviews) == content)
        }
        // The values saved by earlier builds still read.
        #expect(WidgetContent(rawValue: "memoryCount") == .memoryCount && WidgetContent(rawValue: "memoryEntry") == .memoryEntry)
    }
}

@MainActor
struct ReflectionChatSummaryTests {
    /// A long chat keeps its most recent turns for the summary, so a late answer isn't cut off.
    @Test func longChatsKeepTheLatestTurns() {
        var conversation: [ReflectionChat.Message] = []
        for turn in 1...30 {
            conversation.append(ReflectionChat.Message(fromWriter: true, text: "Answer \(turn): " + String(repeating: "words ", count: 20)))
            conversation.append(ReflectionChat.Message(fromWriter: false, text: "A question back " + String(repeating: "hmm ", count: 100)))
        }
        conversation.append(ReflectionChat.Message(fromWriter: true, text: "The realization: I miss mornings outside."))
        let transcript = JournalIntelligence.summaryTranscript(conversation)
        #expect(transcript.contains("The realization: I miss mornings outside."))
        #expect(!transcript.contains("Answer 1: "))
        #expect(transcript.hasPrefix("…"))
        #expect(transcript.count <= 2100)
    }

    @Test func shortChatsAreKeptWhole() {
        let conversation = [ReflectionChat.Message(fromWriter: true, text: "The sunrise."),
                            ReflectionChat.Message(fromWriter: false, text: "What made it stick?")]
        #expect(JournalIntelligence.summaryTranscript(conversation) == "Me: The sunrise.\nCompanion: What made it stick?")
    }
}

@MainActor
struct WidgetPhotoTests {
    /// Cleaning up old photo copies stays inside WidgetPhotos: the App Group's other files (its
    /// shared settings) and the kept photo survive.
    @Test func cleanupOnlyTouchesOtherPhotoCopies() throws {
        let folder = try #require(WidgetSnapshot.photoFolder)
        let root = folder.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let neighbor = root.appending(path: "test-neighbor.txt")
        let keep = folder.appending(path: "entry-1.jpg"), old = folder.appending(path: "entry-2.jpg")
        for file in [neighbor, keep, old] { try Data("x".utf8).write(to: file) }
        defer { try? FileManager.default.removeItem(at: neighbor); try? FileManager.default.removeItem(at: keep) }

        WidgetSync.removePhotos(except: "entry-1.jpg")

        #expect(FileManager.default.fileExists(atPath: neighbor.path), "Files outside WidgetPhotos are left alone")
        #expect(FileManager.default.fileExists(atPath: keep.path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(folder.lastPathComponent == "WidgetPhotos")
    }
}

struct ShareCardTests {
    /// The same wording and rounding as the daily email's "Rewind 3 months and 1 week".
    @Test func relativeDatesAreDaysUnderSixtyThenTwoUnits() throws {
        let today = try #require(JournalDay("2026-11-09"))
        func ago(_ days: Int) throws -> String {
            let date = try #require(Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: today.localDate))
            return JournalDay(localDate: date).relative(to: today)
        }
        #expect(try ago(0) == "Today")
        #expect(try ago(1) == "Yesterday")
        #expect(try ago(36) == "36 days ago")
        #expect(try ago(59) == "59 days ago")
        #expect(try ago(60) == "2 months ago")
        #expect(try ago(97) == "3 months and 1 week ago")
        #expect(try ago(365) == "12 months ago")
        #expect(try ago(430) == "1 year and 2 months ago")
        #expect(try ago(1096) == "3 years ago")
        #expect(JournalDay.span(days: 97) == ["3 months", "1 week"])
    }

    @MainActor
    @Test func cardAddsABandAboveThePhotoAtItsWidth() {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        let card = ShareCard.render(photo, label: "3 years ago")
        if let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] {
            try? card.pngData()?.write(to: URL(fileURLWithPath: "\(dir)/share-card.png"))
        }
        #expect(abs(card.size.width * card.scale - 800) < 1)
        #expect(abs(card.size.height * card.scale - (600 + 88)) < 1) // an 11% band
    }
}

struct DecodingTests {
    @Test func decodesEntryDetail() throws {
        let json = """
        {"entry":{"id":7,"date":"2026-01-02","excerpt":"Hi","image_url":null,"image_processing":false,
        "hashtags":["coffee"],"updated_at":"2026-01-02T10:00:00Z","body_text":"Hi **there**",
        "document":[{"type":"paragraph","runs":[{"text":"Hi "},{"text":"there","bold":true}]},{"type":"rule"}],"songs":[{"title":"Song","artists":["A","B"],"spotify_url":"https://open.spotify.com/track/1"}],
        "web_url":"https://dabble.me/entries/2026/1/2"},"merged":true}
        """
        let envelope = try APIClient.decoder.decode(EntryEnvelope.self, from: Data(json.utf8))
        #expect(envelope.merged == true)
        #expect(envelope.entry.document == [.paragraph(DocumentRun("Hi "), DocumentRun("there", bold: true)), DocumentBlock(type: .rule)])
        #expect(envelope.entry.songs.first?.label == "A, B – Song")
        #expect(envelope.entry.summary.hashtags == ["coffee"])
    }

    /// An opened entry replaces its timeline row's data: songs and dated tags carry over, and the
    /// whole text means nothing's left to load (PR #208 review).
    @Test func summaryKeepsSongsAndDatedTags() throws {
        let json = """
        {"entry":{"id":8,"date":"2026-01-03","excerpt":"Hi","image_url":null,"image_processing":false,
        "hashtags":["Biscuit"],"updated_at":"2026-01-03T10:00:00Z","body_text":"Hi #Biscuit","document":null,
        "songs":[{"title":"Song","artists":["A"],"spotify_url":"https://open.spotify.com/track/1"}],
        "dated_hashtags":[{"tag":"Biscuit","date":"2023-06-08","age":"2 years and 6 months since entry"}],
        "preview_truncated":true,"web_url":"https://dabble.me/entries/2026/1/3"}}
        """
        let summary = try APIClient.decoder.decode(EntryEnvelope.self, from: Data(json.utf8)).entry.summary
        #expect(summary.songs?.first?.title == "Song")
        #expect(summary.datedHashtags?.first?.tag == "Biscuit")
        #expect(summary.previewTruncated == false)
    }

    @Test func decodesMe() throws {
        let json = """
        {"id":1,"email":"a@b.c","first_name":null,"plan":"free","is_pro":false,"timezone":"Mountain Time (US & Canada)",
        "today":"2026-11-07","entry_count":3,"can_write":true,"can_add_photos":false,"can_edit":false,"can_search":false,
        "settings_url":"https://dabble.me/settings","security_url":"https://dabble.me/security",
        "ai_connectors":{"claude_url":"https://claude.ai/x","chatgpt_url":"https://chatgpt.com/x","guide_url":"https://dabble.me/mcp-server",
        "requires_pro":true,"requires_security_setup":false}}
        """
        let me = try APIClient.decoder.decode(Me.self, from: Data(json.utf8))
        #expect(me.canWrite == true)
        #expect(me.canAddPhotos == false)
        #expect(me.today == "2026-11-07")
        #expect(me.aiConnectors?.requiresPro == true)
    }
}

struct PhotoPreparerTests {
    @Test func downscalesAndDropsLocation() throws {
        // A 3000x2000 JPEG with GPS metadata, as an iPhone photo would have.
        let context = try #require(CGContext(data: nil, width: 3000, height: 2000, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        let image = try #require(context.makeImage())
        let original = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(original, UTType.jpeg.identifier as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 39.74, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 104.99, kCGImagePropertyGPSLongitudeRef: "W"]
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        #expect(Self.properties(of: original as Data)[kCGImagePropertyGPSDictionary] != nil)

        let prepared = try PhotoPreparer.prepare(original as Data)
        let output = Self.properties(of: prepared.data)
        #expect(prepared.contentType == "image/jpeg")
        #expect(output[kCGImagePropertyGPSDictionary] == nil)
        #expect(output[kCGImagePropertyPixelWidth] as? Int == 2400)
    }

    @Test func rejectsNonImages() {
        #expect(throws: PhotoError.self) { try PhotoPreparer.prepare(Data("hello".utf8)) }
    }

    private static func properties(of data: Data) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }
}

struct RichTextTests {
    #if canImport(UIKit)
    static var style: RichText.Style { RichText.Style(baseFont: .systemFont(ofSize: 17), textColor: .label) }
    #else
    static var style: RichText.Style { RichText.Style(baseFont: .systemFont(ofSize: 14), textColor: .labelColor) }
    #endif

    static let sample: [DocumentBlock] = [
        .paragraph(DocumentRun("Morning "), DocumentRun("run", bold: true), DocumentRun(", then "),
                   DocumentRun("coffee", italic: true, underline: true), DocumentRun("\nwith "),
                   DocumentRun("Sam", link: "https://example.com/sam")),
        DocumentBlock(type: .bullet, runs: [DocumentRun("eggs")]),
        DocumentBlock(type: .bullet, runs: [DocumentRun("toast", bold: true, italic: true)]),
        .paragraph(DocumentRun("Afterwards")),
        DocumentBlock(type: .rule),
        DocumentBlock(type: .number, runs: [DocumentRun("one")]),
        DocumentBlock(type: .number, runs: [DocumentRun("two")]),
    ]

    @Test func laysOutBlocksAsEditableText() {
        let text = RichText.attributedString(from: Self.sample, style: Self.style).string
        // One line per paragraph (Return starts the next; paragraph spacing makes the gap); a
        // line break inside a paragraph is a line separator.
        #expect(text == "Morning run, then coffee\u{2028}with Sam\n• eggs\n• toast\nAfterwards\n⸻\n1. one\n2. two")
    }

    @Test func roundTripsFormatting() {
        let text = RichText.attributedString(from: Self.sample, style: Self.style)
        #expect(RichText.blocks(from: text) == Self.sample)
    }

    @Test func readsTypedListsAndDividers() {
        let typed = NSAttributedString(string: "Shopping\n- milk\n2) bread\n---\n\n  Done  \n\n\n")
        #expect(RichText.blocks(from: typed) == [
            .paragraph(DocumentRun("Shopping")),
            DocumentBlock(type: .bullet, runs: [DocumentRun("milk")]),
            DocumentBlock(type: .number, runs: [DocumentRun("bread")]),
            DocumentBlock(type: .rule),
            .paragraph(DocumentRun("Done")),
        ])
    }

    /// Each Return is a new paragraph, spaced apart a little; blank lines don't add more.
    @Test func eachLineIsAParagraph() {
        let typed = NSMutableAttributedString(string: "First line\nSecond line\n\nThird", attributes: [.font: Self.style.baseFont])
        #expect(RichText.blocks(from: typed) == [.paragraph(DocumentRun("First line")), .paragraph(DocumentRun("Second line")),
                                                 .paragraph(DocumentRun("Third"))])
        RichText.applyListIndents(to: typed, font: Self.style.baseFont)
        let style = typed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect((style?.paragraphSpacing ?? 0) > 0)
    }

    @Test func dropsEmptyItemsAndAttachments() {
        let typed = NSAttributedString(string: "• \n\u{FFFC}\nHi\u{FFFC}")
        #expect(RichText.blocks(from: typed) == [.paragraph(DocumentRun("Hi"))])
    }

    @Test func detectsListPrefixes() {
        #expect(RichText.listPrefix(in: "• a") == RichText.ListPrefix(kind: .bullet, length: 2, number: 0))
        #expect(RichText.listPrefix(in: "12. a") == RichText.ListPrefix(kind: .number, length: 4, number: 12))
        #expect(RichText.listPrefix(in: "2026. a") == nil)
        #expect(RichText.listPrefix(in: "3.14 is pi") == nil)
    }

    @Test func encodesOnlySetFormatting() throws {
        let data = try JSONEncoder().encode(DocumentRun("hi", bold: true))
        #expect(String(decoding: data, as: UTF8.self) == #"{"bold":true,"text":"hi"}"# ||
                String(decoding: data, as: UTF8.self) == #"{"text":"hi","bold":true}"#)
    }
}

struct HashtagLinkTests {
    @Test func linksHashtagsButNotLookalikes() {
        let text = RichText.linkingHashtags(in: AttributedString("Great #hike today. C# and https://x.test/#top stay plain. #2026goals too"))
        let links = text.runs.compactMap { run in run.link.map { (String(text[run.range].characters), $0) } }
        #expect(links.map(\.0) == ["#hike", "#2026goals"])
        #expect(links.compactMap { RichText.hashtag(from: $0.1) } == ["hike", "2026goals"])
    }

    @Test func leavesExistingLinksAlone() {
        var text = AttributedString("#notatag")
        text.link = URL(string: "https://example.com")
        #expect(RichText.linkingHashtags(in: text).runs.first?.link == URL(string: "https://example.com"))
    }
}

struct WidgetSnapshotTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
    }

    private func snapshot(day: String, wrote: Bool, count: Int?, memories: Int = 0) -> WidgetSnapshot {
        WidgetSnapshot(day: day, wroteToday: wrote, yearCount: count, memories: memories, memoriesFirstYear: nil, prompt: "Hi")
    }

    @Test func sameDayShowsTheSnapshot() {
        let state = snapshot(day: "2026-11-08", wrote: true, count: 36, memories: 2).state(on: date(8), calendar: calendar)
        #expect(state.wroteToday && state.yearCount == 36 && state.memories == 2)
    }

    @Test func aNewDayIsUnwrittenAndKeepsTheYearsCount() {
        let state = snapshot(day: "2026-11-05", wrote: true, count: 36, memories: 2).state(on: date(8), calendar: calendar)
        #expect(!state.wroteToday && state.yearCount == 36 && state.memories == nil)
    }

    @Test func aNewYearStartsTheCountAgain() {
        let newYear = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 9))!
        #expect(snapshot(day: "2026-12-31", wrote: true, count: 40).state(on: newYear, calendar: calendar).yearCount == 0)
    }

    /// A snapshot saved by a build that still tracked the streak has no count yet.
    @Test func olderSnapshotsStillLoad() throws {
        let old = #"{"day":"2026-11-08","wroteToday":true,"streak":4,"memories":0,"prompt":"Hi"}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))
        #expect(snapshot.state(on: date(8), calendar: calendar).yearCount == 0)
    }
}

@MainActor
struct JournalIntelligenceTests {
    @Test func readsHashtagsFromAReply() {
        #expect(JournalIntelligence.hashtags(in: "#hiking #Yosemite, #2026trip and C# code") == ["hiking", "Yosemite", "2026trip"])
    }
}

struct ListIndentTests {
    @Test func listItemsHangAndParagraphsDont() {
        let blocks = [DocumentBlock.paragraph(DocumentRun("Intro")), DocumentBlock(type: .bullet, runs: [DocumentRun("Item")])]
        let font = PlatformFont.systemFont(ofSize: 17)
        let text = RichText.attributedString(from: blocks, style: RichText.Style(baseFont: font, textColor: .black))
        let string = text.string as NSString
        let bullet = string.range(of: "Item").location
        let indent = (text.attribute(.paragraphStyle, at: bullet, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
        let paragraph = (text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
        #expect(indent > 5)
        #expect(paragraph == 0)
    }
}

/// Reflects on a real entry with the on-device model (simulator or device with Apple Intelligence).
/// Opt-in: TEST_RUNNER_DABBLE_REFLECT_FILE points at a text file outside the repo, so personal
/// entries that trip the safety guardrails can be checked without committing them.
@Test(.enabled(if: ProcessInfo.processInfo.environment["DABBLE_REFLECT_FILE"] != nil))
func reflectsOnAHardEntry() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["DABBLE_REFLECT_FILE"])
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let reflection = try await JournalIntelligence.reflection(on: text, date: "Sunday, April 26, 2026", ago: "196 days ago",
                                                              today: "Sunday, November 8, 2026", firstName: "Paul", recent: [])
    print("REFLECTION: \(reflection)")
    #expect(!reflection.isEmpty)
}

struct NestedListTests {
    private let blocks = [
        DocumentBlock(type: .number, runs: [DocumentRun("Outer", bold: true)]),
        DocumentBlock(type: .number, runs: [DocumentRun("First in")], level: 1),
        DocumentBlock(type: .number, runs: [DocumentRun("Second in")], level: 1),
        DocumentBlock(type: .bullet, runs: [DocumentRun("Deeper")], level: 2),
        DocumentBlock(type: .number, runs: [DocumentRun("Next")]),
    ]

    /// A list inside an item counts from 1, and the outer list carries on after it.
    @Test func listsInsideListsAreSetInAndNumberedOnTheirOwn() {
        let text = RichText.segments(for: blocks).map(\.text).joined()
        #expect(text == "1. Outer\n    1. First in\n    2. Second in\n        • Deeper\n2. Next")
        #expect(RichText.listNumbers(for: blocks) == [1, 1, 2, 0, 2])
    }

    @Test func levelsRoundTripThroughTheEditorsText() {
        let style = RichText.Style(baseFont: .systemFont(ofSize: 17), textColor: .black)
        #expect(RichText.blocks(from: RichText.attributedString(from: blocks, style: style)) == blocks)
    }

    @Test func levelsDecodeAndEncode() throws {
        let json = #"[{"type":"bullet","runs":[{"text":"a"}]},{"type":"bullet","runs":[{"text":"b"}],"level":1}]"#
        let decoded = try JSONDecoder().decode([DocumentBlock].self, from: Data(json.utf8))
        #expect(decoded.map(\.depth) == [0, 1])
        let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        #expect(encoded.contains(#""level":1"#) && encoded.components(separatedBy: "level").count == 2)
    }

    @Test func spacesBeforeAMarkerSetItsLevel() {
        #expect(RichText.listPrefix(in: "- a")?.level == 0)
        #expect(RichText.listPrefix(in: "    - a")?.level == 1)
        #expect(RichText.listPrefix(in: "   2. a")?.level == 1)
        #expect(RichText.listPrefix(in: "\t\t• a")?.level == 2)
        #expect(RichText.listPrefix(in: "    - a")?.length == 6)
        #expect(RichText.listPrefix(in: "    plain") == nil)
    }
}

struct TrailingHashtagTests {
    @Test func datedTagsAtTheEndAreDropped() {
        #expect(RichText.droppingTrailing(hashtags: ["Leo"], songLinks: false, from: "Park day. #leo") == "Park day.")
        #expect(RichText.droppingTrailing(hashtags: ["Leo", "Mila"], songLinks: false, from: "Park day.\n\n#Leo #Mila\n") == "Park day.")
        #expect(RichText.droppingTrailing(hashtags: ["Leo"], songLinks: false, from: "Park day. #Leo #park") == "Park day. #park")
    }

    @Test func otherTagsAndTagsInTheTextStay() {
        #expect(RichText.droppingTrailing(hashtags: ["Leo"], songLinks: false, from: "#Leo loved the park.") == "#Leo loved the park.")
        #expect(RichText.droppingTrailing(hashtags: ["Leo"], songLinks: false, from: "Park day. #park") == "Park day. #park")
        #expect(RichText.droppingTrailing(hashtags: [], songLinks: false, from: "Park day. #Leo") == "Park day. #Leo")
        #expect(RichText.droppingTrailing(hashtags: ["Leo"], songLinks: false, from: "#Leo") == "#Leo", "Nothing else to show")
    }

    @Test func theLastBlocksTagsAreDropped() {
        let entry = [DocumentBlock.paragraph(DocumentRun("Park "), DocumentRun("day", bold: true), DocumentRun(". #Leo #park"))]
        #expect(RichText.droppingTrailing(hashtags: ["leo"], songLinks: false, from: entry)
            == [DocumentBlock.paragraph(DocumentRun("Park "), DocumentRun("day", bold: true), DocumentRun(". "), DocumentRun("#park"))])
        let tagsLast = [DocumentBlock.paragraph(DocumentRun("Park day.")), DocumentBlock.paragraph(DocumentRun("#Leo"))]
        #expect(RichText.droppingTrailing(hashtags: ["Leo"], songLinks: false, from: tagsLast) == [DocumentBlock.paragraph(DocumentRun("Park day."))])
        #expect(RichText.droppingTrailing(hashtags: ["Leo"], songLinks: false, from: [tagsLast[1]]) == [tagsLast[1]])
    }
}

struct TrailingSongLinkTests {
    private let link = "https://open.spotify.com/track/5vUNRJsvEOUsz4sbKkJpFr"

    @Test func aSongLinkAtTheEndIsDropped() {
        #expect(RichText.droppingTrailing(hashtags: [], songLinks: true, from: "Love it.\n\n\(link)") == "Love it.")
        #expect(RichText.droppingTrailing(hashtags: [], songLinks: true, from: "Love it. [\(link)](\(link)?si=abc)") == "Love it.")
        #expect(RichText.droppingTrailing(hashtags: ["Leo"], songLinks: true, from: "Love it. \(link) #Leo") == "Love it.")
        #expect(RichText.droppingTrailing(hashtags: ["Leo"], songLinks: true, from: "Love it. #Leo \(link)") == "Love it.")
    }

    @Test func linksElsewhereAndOtherLinksStay() {
        #expect(RichText.droppingTrailing(hashtags: [], songLinks: true, from: "\(link) is the one.") == "\(link) is the one.")
        #expect(RichText.droppingTrailing(hashtags: [], songLinks: true, from: "Read https://dabble.me") == "Read https://dabble.me")
        #expect(RichText.droppingTrailing(hashtags: [], songLinks: false, from: "Love it. \(link)") == "Love it. \(link)")
        #expect(RichText.droppingTrailing(hashtags: [], songLinks: true, from: link) == link, "Nothing else to show")
    }

    @Test func theLastBlocksSongLinkIsDropped() {
        let text = DocumentBlock.paragraph(DocumentRun("Love it."))
        let own = DocumentBlock.paragraph(DocumentRun(link, link: link))
        #expect(RichText.droppingTrailing(hashtags: [], songLinks: true, from: [text, own]) == [text])
        let inline = DocumentBlock.paragraph(DocumentRun("Love it. "), DocumentRun("this song", link: link), DocumentRun(" #Leo"))
        #expect(RichText.droppingTrailing(hashtags: ["leo"], songLinks: true, from: [inline]) == [text])
        let bare = DocumentBlock.paragraph(DocumentRun("Love it. \(link)"))
        #expect(RichText.droppingTrailing(hashtags: [], songLinks: true, from: [bare]) == [text])
        #expect(RichText.droppingTrailing(hashtags: [], songLinks: true, from: [own]) == [own])
    }
}

@MainActor
struct ReminderTests {
    private func plan(_ json: String) throws -> ReminderPlan {
        try APIClient.decoder.decode(ReminderPlan.self, from: Data(json.utf8))
    }

    /// How long ago is as of the day the reminder shows, not the day it was scheduled.
    @Test func memoriesAreLabelledAsOfTheirDay() throws {
        let plan = try plan(#"""
        {"email_hour":21,"days":[
          {"date":"2026-11-20","kind":"on_this_day","count":2,"entry":{"id":7,"date":"2023-11-20","excerpt":"Snow.","image_url":null}},
          {"date":"2026-11-21","kind":"rewind","count":1,"entry":{"id":9,"date":"2026-11-14","excerpt":"","image_url":"https://x.test/a.jpg"}}]}
        """#)
        #expect(plan.emailHour == 21)
        #expect(ReminderScheduler.label(for: plan.days[0], on: "2026-11-20") == "On This Day · 3 years ago")
        #expect(ReminderScheduler.label(for: plan.days[1], on: "2026-11-21") == "Rewind · 7 days ago")
    }
}


struct RewindTests {
    private func summary(_ id: Int, _ date: String, _ text: String, tags: [String] = [], image: String? = nil, songs: [Song]? = nil) -> EntrySummary {
        EntrySummary(id: id, date: date, excerpt: text, imageUrl: image, imageProcessing: false, hashtags: tags,
                     updatedAt: "\(date)T12:00:00Z", previewText: text, songs: songs)
    }

    private var year: Rewind {
        let song = Song(title: "Holocene", artists: ["Bon Iver"], spotifyUrl: URL(string: "https://open.spotify.com/track/abc")!)
        return Rewind.build(year: 2026, summaries: [
            summary(1, "2026-01-03", "Leo and Silas built a fort. **Great** day. #Leo", tags: ["Leo"]),
            summary(2, "2026-01-10", "Leo lost a tooth in Denver. https://open.spotify.com/track/abc", songs: [song]),
            summary(3, "2026-03-07", "Flew to Lisbon with Katelyn. I felt lucky to be there with her.", image: "https://x.test/a.jpg"),
            summary(4, "2026-03-14", "Then Silas rode a bike while Alex cheered. #bikes #Leo", tags: ["bikes", "Leo"]),
            summary(5, "2026-03-21", "Quiet Saturday at home.", songs: [song]),
            summary(6, "2025-12-31", "Last year's entry about Leo."),
        ], ownName: "Alex", tagDates: [TagDate(id: 1, tag: "Leo", date: "2018-01-18")])
    }

    @Test func countsTheYearsEntriesWordsAndPhotos() {
        #expect(year.entries.map(\.id) == [1, 2, 3, 4, 5], "Only this year's, oldest first")
        #expect(year.entries[0].text == "Leo and Silas built a fort. Great day. #Leo", "Markdown marks go")
        #expect(year.entries[1].text == "Leo lost a tooth in Denver.", "A song's link goes")
        #expect(year.wordCount == 9 + 6 + 13 + 10 + 4)
        #expect(year.photos.map(\.id) == [3])
        #expect(year.span == "January to March")
    }

    @Test func findsTheBiggestMonthTheWeekdayAndTheLongestGap() {
        #expect(year.biggestMonth?.month == 3 && year.biggestMonth?.count == 3)
        #expect(year.busiestWeekday?.name == "Saturday" && year.busiestWeekday?.count == 5)
        #expect(year.longestGap == Rewind.Gap(days: 56, from: JournalDay("2026-01-10")!, to: JournalDay("2026-03-07")!))
    }

    /// People by first name, in two entries or more, without the writer; a song and a tag once each.
    @Test func ranksPeopleAndGathersSongsHashtagsAndMilestones() {
        #expect(year.people.map(\.name) == ["Leo", "Silas"])
        #expect(year.people.first?.entryIDs == [1, 2, 4])
        #expect(!year.people.contains { $0.name == "Alex" })
        #expect(year.songs.count == 1 && year.songs.first?.day.iso == "2026-01-10")
        #expect(year.hashtags.map { "\($0.tag) \($0.count)" } == ["Leo 2", "bikes 1"])
        #expect(year.milestones == [Rewind.Milestone(tag: "Leo", years: 8)])
    }

    /// Without name recognition, names are the words capitalized mid-sentence, and #Tags.
    @Test func findsNamesByTheirCapitals() {
        #expect(Rewind.capitalizedNames(in: "Went to Yosemite with Sam. Sam’s idea. I think Maya knew. #Biscuit slept on Friday.")
            == ["Yosemite", "Sam", "Maya", "Biscuit"])
        #expect(Rewind.capitalizedNames(in: "The list so far:\nThe puzzle\nCards with Sam") == ["Sam"], "A new line starts a sentence")
    }

    @Test func offersTheWritersOwnSentencesForLineOfTheYear() {
        let lines = year.lineCandidates().map(\.text)
        #expect(lines == ["I felt lucky to be there with her."])
    }

    @Test func theSeasonIsNovemberToJanuary() throws {
        #expect(RewindSeason.year(on: try #require(JournalDay("2026-11-01"))) == 2026)
        #expect(RewindSeason.year(on: try #require(JournalDay("2026-12-31"))) == 2026)
        #expect(RewindSeason.year(on: try #require(JournalDay("2027-01-15"))) == 2026)
        #expect(RewindSeason.year(on: try #require(JournalDay("2027-02-01"))) == nil)
        #expect(RewindSeason.year(on: try #require(JournalDay("2026-10-31"))) == nil)
    }
}
