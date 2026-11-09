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

    @Test func decodesMe() throws {
        let json = """
        {"id":1,"email":"a@b.c","first_name":null,"plan":"free","is_pro":false,"timezone":"Mountain Time (US & Canada)",
        "today":"2026-11-07","entry_count":3,"can_write":true,"can_add_photos":false,"can_edit":false,"can_search":false,
        "settings_url":"https://dabble.me/settings","security_url":"https://dabble.me/security",
        "ai_connectors":{"claude_url":"https://claude.ai/x","chatgpt_url":"https://chatgpt.com/x","guide_url":"https://dabble.me/mcp-server",
        "requires_pro":true,"requires_security_setup":true}}
        """
        let me = try APIClient.decoder.decode(Me.self, from: Data(json.utf8))
        #expect(me.canWrite == true)
        #expect(me.canAddPhotos == false)
        #expect(me.today == "2026-11-07")
        #expect(me.aiConnectors?.requiresSecuritySetup == true)
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
        #expect(text == "Morning run, then coffee\nwith Sam\n\n• eggs\n• toast\n\nAfterwards\n\n⸻\n\n1. one\n2. two")
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

    private func snapshot(day: String, wrote: Bool, streak: Int, memories: Int = 0) -> WidgetSnapshot {
        WidgetSnapshot(day: day, wroteToday: wrote, streak: streak, memories: memories, memoriesFirstYear: nil, prompt: "Hi")
    }

    @Test func sameDayShowsTheSnapshot() {
        let state = snapshot(day: "2026-11-08", wrote: true, streak: 4, memories: 2).state(on: date(8), calendar: calendar)
        #expect(state.wroteToday && state.streak == 4 && state.memories == 2)
    }

    @Test func aStreakSurvivesTheNextDayUntilItsWritten() {
        let state = snapshot(day: "2026-11-07", wrote: true, streak: 4, memories: 2).state(on: date(8), calendar: calendar)
        #expect(!state.wroteToday && state.streak == 4 && state.memories == nil)
    }

    @Test func anUnwrittenDayEndsTheStreak() {
        #expect(snapshot(day: "2026-11-07", wrote: false, streak: 3).state(on: date(8), calendar: calendar).streak == 0)
        #expect(snapshot(day: "2026-11-05", wrote: true, streak: 9).state(on: date(8), calendar: calendar).streak == 0)
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
