import Foundation
import ImageIO
import UIKit
import Testing
import UniformTypeIdentifiers
@testable import DabbleMe

struct NativeAuthTests {
    @Test func base64URLRoundTripsWithoutPadding() throws {
        let bytes = Data([0xfb, 0xff, 0xfe, 0x00, 0x01])
        let encoded = NativeAuth.base64URL(bytes)
        #expect(encoded == "-__-AAE")
        #expect(NativeAuth.data(base64URL: encoded) == bytes)
    }

    @Test func passkeyConfirmationKeepsWebAuthnKeys() throws {
        let assertion = PasskeyAssertion(credentialID: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]),
                                         signature: Data([4]), userID: Data("7".utf8))
        let challenge = try APIClient.decoder.decode(NativeAuth.PasskeyChallenge.self,
                                                     from: Data(#"{"challenge_token":"t","challenge":"c","rp_id":"dabble.me"}"#.utf8))
        let json = try JSONEncoder().encode(NativeAuth.PasskeyConfirmation(assertion: assertion, challenge: challenge))
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["challenge_token"] as? String == "t")
        let credential = try #require(object["credential"] as? [String: Any])
        #expect(credential["rawId"] as? String == "AQ")
        let response = try #require(credential["response"] as? [String: Any])
        #expect(Set(response.keys) == ["clientDataJSON", "authenticatorData", "signature", "userHandle"])
        #expect(response["userHandle"] as? String == "Nw")
    }

    @Test func newPasskeyKeepsWebAuthnKeys() throws {
        let registration = PasskeyRegistration(credentialID: Data([1]), clientDataJSON: Data([2]), attestationObject: Data([3]))
        let creation = try APIClient.decoder.decode(NativeAuth.PasskeyCreation.self, from: Data(
            #"{"challenge_token":"t","challenge":"c","rp_id":"dabble.me","user_id":"Nw","user_name":"a@b.c","exclude_credentials":[]}"#.utf8))
        #expect(NativeAuth.data(base64URL: creation.userId) == Data("7".utf8))
        let json = try JSONEncoder().encode(NativeAuth.NewPasskey(registration: registration, creation: creation,
                                                                   nickname: "n", setupToken: "s", password: nil))
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["challenge_token"] as? String == "t")
        #expect(object["setup_token"] as? String == "s")
        #expect(object["current_password"] == nil)
        let credential = try #require(object["credential"] as? [String: Any])
        let response = try #require(credential["response"] as? [String: Any])
        #expect(Set(response.keys) == ["clientDataJSON", "attestationObject"])
    }

    @Test func otpRequiredAsksForTheCode() {
        let body = Data(#"{"error":"otp_required","message":"Enter the code."}"#.utf8)
        #expect(NativeAuth.failure(status: 401, data: body) == .needsCode)
    }

    @Test func throttledSaysToWait() {
        #expect(NativeAuth.failure(status: 429, data: Data("Retry later".utf8)) == .message("Too many tries. Wait a few minutes, then try again."))
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
struct HashtagTypingTests {
    /// A "#" and a letter at the cursor is a hashtag being typed; a number first, or a "#" inside a word, isn't.
    @Test func findsTheHashtagBeingTyped() {
        func typed(_ text: String, at cursor: Int? = nil) -> String? {
            let string = text as NSString
            return RichTextEditorModel.hashtagBeingTyped(in: string, cursor: cursor ?? string.length)?.prefix
        }
        #expect(typed("Walked with #L") == "L")
        #expect(typed("Walked with #Leo_2") == "Leo_2")
        #expect(typed("#hik") == "hik")
        #expect(typed("#hiking is fun", at: 4) == "hik") // the cursor inside it: what's before the cursor
        #expect(typed("Walked with #") == nil)
        #expect(typed("Room #12") == nil)
        #expect(typed("#1st") == nil)
        #expect(typed("C#m") == nil)
        #expect(typed("##tag") == nil)
        #expect(typed("#Leo ") == nil)
        #expect(typed("no tag here") == nil)
        let found = RichTextEditorModel.hashtagBeingTyped(in: "Hi #Le" as NSString, cursor: 6)
        #expect(found?.range == NSRange(location: 3, length: 3))
        // Inside one: the whole hashtag is what a choice replaces, not just up to the cursor.
        let inside = RichTextEditorModel.hashtagBeingTyped(in: "#hiking is fun" as NSString, cursor: 4)
        #expect(inside?.prefix == "hik")
        #expect(inside?.range == NSRange(location: 0, length: 7))
    }

    /// Finishing a hashtag keeps what was typed as it was typed, and adds the rest.
    @Test func finishingKeepsTheWritersCapitals() {
        #expect(RichTextEditorModel.completion(of: "l", with: "Leo") == "leo")
        #expect(RichTextEditorModel.completion(of: "L", with: "leo") == "Leo")
        #expect(RichTextEditorModel.completion(of: "HI", with: "hiking") == "HIking")
        #expect(RichTextEditorModel.completion(of: "hik", with: "Hiking") == "hiking")
        #expect(RichTextEditorModel.completion(of: "x", with: "Leo") == "Leo") // not its beginning: the tag as it is
    }

    /// The writer's tags that start with it, the first of each spelling, without the one typed in full.
    @Test func offersTagsThatStartThatWay() {
        let tags = ["hiking", "Leo", "Hike", "leo", "home", "hi"]
        #expect(ComposeView.hashtagCompletions(for: "hi", from: tags) == ["hiking", "Hike"])
        #expect(ComposeView.hashtagCompletions(for: "L", from: tags) == ["Leo"])
        #expect(ComposeView.hashtagCompletions(for: "leo", from: tags).isEmpty)
        #expect(ComposeView.hashtagCompletions(for: "zz", from: tags).isEmpty)
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

    /// The medium widget's right side opens Today, scrolled to what it shows.
    @Test func rightSideLinksToWhatItShows() {
        func entry(memories: Int? = nil, note: String? = nil, title: String? = nil, text: String? = nil, id: Int? = nil) -> WidgetEntry {
            WidgetEntry(date: .now, signedIn: true, wroteToday: false, yearCount: 3, memories: memories, prompt: "Hi",
                        memoryNote: note, entryTitle: title, entryText: text, entryID: id)
        }
        // An entry looked back on: Today, at that entry (a photo alone, without words, too).
        #expect(entry(memories: 2, title: "1 year ago · 2025", text: "Snow.", id: 7).detailURL.absoluteString == "me.dabble.app:/today/entry/7")
        #expect(entry(title: "31 days ago", text: "", id: 9).detailURL.absoluteString == "me.dabble.app:/today/entry/9")
        // Today's own entry: Today, where it's at the top.
        #expect(entry(title: WidgetEntry.todayTitle, text: "Rain.", id: 8).detailURL == WidgetSnapshot.todayURL)
        // A count or a note, without the entry: the look back.
        #expect(entry(memories: 2).detailURL == WidgetSnapshot.todayLookBackURL)
        #expect(entry(note: "You have a memory from 36 days ago.").detailURL == WidgetSnapshot.todayLookBackURL)
        // A prompt: Today.
        #expect(entry().detailURL == WidgetSnapshot.todayURL)
    }

    /// And the app reads those links back (not an older widget's).
    @Test func readsTheWidgetsLinks() throws {
        #expect(TodayFocus(WidgetSnapshot.todayEntryURL(7)) == .entry(7))
        #expect(TodayFocus(WidgetSnapshot.todayLookBackURL) == .lookBack)
        #expect(TodayFocus(WidgetSnapshot.todayURL) == .top)
        for old in ["me.dabble.app:/entry/7", "me.dabble.app:/today/edit", "me.dabble.app:/write", "me.dabble.app:/today/entry/x"] {
            #expect(TodayFocus(try #require(URL(string: old))) == nil)
        }
    }
}

@MainActor
struct ReflectionChatSummaryTests {
    /// A companion's turn is kept as the question it ends on: that's what was answered next.
    @Test func companionTurnsComeDownToTheirQuestion() {
        #expect(JournalIntelligence.closingQuestion(in: "That walk sounds lovely. It stayed with you. **What made it stick?**") == "What made it stick?")
        #expect(JournalIntelligence.closingQuestion(in: "Was it the light? Or the quiet?\nWhich would you go back for?") == "Which would you go back for?")
        #expect(JournalIntelligence.closingQuestion(in: "That sounds like a good day.") == nil)
    }

    /// The model's reply is read as a question and an answer, whatever it gets wrong about the form.
    @Test func readsTheQuestionAndTheAnswer() {
        typealias Summary = JournalIntelligence.ChatSummary
        let asked = "What made it stick?"
        #expect(JournalIntelligence.parseChatSummary("QUESTION: What made the sunrise stay with me?\nANSWER: The light on the water, and that nobody else was up.", askedFirst: asked)
                == Summary(question: "What made the sunrise stay with me?", answer: "The light on the water, and that nobody else was up."))
        #expect(JournalIntelligence.parseChatSummary("**Question:** \"Why the sunrise?\"\n**Answer:** It was quiet.", askedFirst: asked)
                == Summary(question: "Why the sunrise?", answer: "It was quiet."))
        // No question written, or no labels at all: the reflection's own question stands in.
        #expect(JournalIntelligence.parseChatSummary("ANSWER: It was quiet.", askedFirst: asked) == Summary(question: asked, answer: "It was quiet."))
        #expect(JournalIntelligence.parseChatSummary("It was quiet.", askedFirst: asked) == Summary(question: asked, answer: "It was quiet."))
        #expect(JournalIntelligence.parseChatSummary("QUESTION: Why?\nANSWER:", askedFirst: asked) == nil)
    }

    /// The sum-up is the questions that were answered, each with its answer: one asked after the
    /// writer's last answer isn't in it, and replies sent one after another are one answer.
    @Test func onlyAnsweredQuestionsAreSummedUp() {
        let conversation = [ReflectionChat.Message(fromWriter: false, text: "A kind paragraph. **What made it stick?**"),
                            ReflectionChat.Message(fromWriter: true, text: "The sunrise."),
                            ReflectionChat.Message(fromWriter: true, text: "And the quiet."),
                            ReflectionChat.Message(fromWriter: false, text: "Lovely. **Who would you take back there?**"),
                            ReflectionChat.Message(fromWriter: true, text: "Sam."),
                            ReflectionChat.Message(fromWriter: false, text: "**What would you show Sam first?**")]
        let exchanges = JournalIntelligence.exchanges(in: conversation)
        #expect(exchanges.map(\.question) == ["What made it stick?", "Who would you take back there?"])
        #expect(exchanges.map(\.answer) == ["The sunrise.\nAnd the quiet.", "Sam."])
    }

    /// The sum-up goes under the entry: a sentence the entry already has doesn't go in again.
    @Test func whatTheEntryAlreadySaysIsNotRepeated() {
        let entry = "We hiked the Mist Trail before sunrise. Sam sang the whole way down."
        let answer = "We hiked the Mist Trail before sunrise. What stayed with me was how quiet it was at the top."
        #expect(JournalIntelligence.removingSentences(of: answer, alreadyIn: entry) == "What stayed with me was how quiet it was at the top.")
        // (Whatever its capitals or punctuation; a couple of shared words isn't a repeat.)
        #expect(JournalIntelligence.removingSentences(of: "we hiked the mist trail before sunrise! It was cold.", alreadyIn: entry) == "It was cold.")
        #expect(JournalIntelligence.removingSentences(of: "It was quiet.", alreadyIn: "It was quiet. And cold.") == "It was quiet.")
        // All but word for word is a repeat too.
        #expect(JournalIntelligence.removingSentences(of: "I was really glad Katelyn attended with me. Mostly I'm tired of it dragging on.",
                                                      alreadyIn: "I was really glad that Katelyn attended with me.") == "Mostly I'm tired of it dragging on.")
        // A word of its own changes what it says: it stays.
        #expect(JournalIntelligence.removingSentences(of: "I was not glad Katelyn came with me.", alreadyIn: "I was glad Katelyn came with me.") == "I was not glad Katelyn came with me.")
    }

}

struct NewEntryControlRequestTests {
    /// The control's word to the app is heard once, and only for a minute.
    @Test func isTakenOnceAndExpires() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        NewEntryControlRequest.record(at: now)
        #expect(NewEntryControlRequest.take(at: now.addingTimeInterval(2)))
        #expect(!NewEntryControlRequest.take(at: now.addingTimeInterval(3)))
        NewEntryControlRequest.record(at: now)
        #expect(!NewEntryControlRequest.take(at: now.addingTimeInterval(NewEntryControlRequest.lifetime + 1)))
        #expect(!NewEntryControlRequest.take(at: now.addingTimeInterval(4)), "An expired one is gone too")
    }
}

struct EntryAgoTests {
    /// An open entry's title: days up to 60, then years and months in full, without days.
    @Test func agoIsDaysThenYearsAndMonths() throws {
        let today = try #require(JournalDay("2026-11-15"))
        func ago(_ iso: String) throws -> String { try #require(JournalDay(iso)).ago(from: today) }
        #expect(try ago("2026-11-15") == "Today")
        #expect(try ago("2026-11-14") == "Yesterday")
        #expect(try ago("2026-10-31") == "15 days ago")
        #expect(try ago("2026-09-16") == "60 days ago")
        #expect(try ago("2026-09-15") == "2 months ago")
        #expect(try ago("2026-08-25") == "3 months ago") // 2 months and 21 days: nearer three
        #expect(try ago("2025-11-15") == "1 year ago")
        #expect(try ago("2025-11-03") == "1 year ago")
        #expect(try ago("2021-09-12") == "5 years, 2 months ago")
        #expect(try ago("2021-11-25") == "5 years ago") // 4 years, 11 months and 21 days
    }

    /// A long span keeps its months (a photo's band once read "14 years ago" for this).
    @Test func aLongSpanKeepsItsMonths() throws {
        let today = try #require(JournalDay("2026-11-15"))
        let day = try #require(JournalDay("2012-08-10"))
        #expect(day.ago(from: today) == "14 years, 3 months ago")
    }

    /// Counted in days back: days through 60, then months and years, never weeks.
    @Test func sixtyDaysIsTheLastCountedInDays() throws {
        let today = try #require(JournalDay("2026-11-09"))
        func ago(_ days: Int) throws -> String {
            let date = try #require(Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: today.localDate))
            return JournalDay(localDate: date).ago(from: today)
        }
        #expect(try ago(36) == "36 days ago")
        #expect(try ago(60) == "60 days ago")
        #expect(try ago(61) == "2 months ago")
        #expect(try ago(97) == "3 months ago") // 3 months and 5 days
        #expect(try ago(365) == "1 year ago")
        #expect(try ago(430) == "1 year, 2 months ago")
        #expect(try ago(1096) == "3 years ago")
    }
}

struct DatedTagAgeTests {
    /// A dated tag's age, as its pill shows it: units abbreviated, two at most, from either wording the server has used.
    @MainActor @Test func agesAreAbbreviatedOnThePill() {
        #expect(HashtagPill.shortAge("7 years, 11 months") == "7yrs, 11mos")
        #expect(HashtagPill.shortAge("1 year and 5 months since entry") == "1yr, 5mos")
        #expect(HashtagPill.shortAge("9 years, 2 days") == "9yrs, 2days")
        #expect(HashtagPill.shortAge("3 weeks, 1 day") == "3wks, 1day")
        #expect(HashtagPill.shortAge("1 month") == "1mo")
        // A tag dated after the entry.
        #expect(HashtagPill.shortAge("3 months and 2 days from entry") == "In 3mos, 2days")
        #expect(HashtagPill.shortAge("today") == "Today")
    }
}

struct MorningRuleTests {
    /// "New Entry" before 10 AM is yesterday's if unwritten: by the journal's clock, not the phone's.
    @MainActor @Test func morningIsJudgedInTheJournalsTimeZone() throws {
        let denver = try #require(TimeZone(identifier: "America/Denver"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        // 9:30 AM in Denver (16:30 UTC) is 1:30 AM the next day in Tokyo; 10:00 is still morning, 10:01 isn't.
        let nineThirty = try #require(ISO8601DateFormatter().date(from: "2026-11-14T16:30:00Z"))
        #expect(AppModel.isMorning(at: nineThirty, in: denver))
        #expect(AppModel.isMorning(at: nineThirty.addingTimeInterval(30 * 60), in: denver))
        #expect(!AppModel.isMorning(at: nineThirty.addingTimeInterval(31 * 60), in: denver))
        // The same moments in a journal kept on Tokyo time: 1:30 AM, then 3 PM.
        #expect(AppModel.isMorning(at: nineThirty, in: tokyo))
        #expect(!AppModel.isMorning(at: nineThirty.addingTimeInterval(-11 * 3600), in: tokyo))
    }
}

struct AppLinkTests {
    /// The dabble.me pages the app opens itself; anything else is left to the browser.
    @Test func readsTheLinksTheAppOpens() throws {
        func link(_ address: String) throws -> AppLink? { AppLink(try #require(URL(string: address))) }
        #expect(try link("https://dabble.me/entries/") == .journal)
        #expect(try link("https://dabble.me/entries") == .journal)
        #expect(try link("https://dabble.me/today") == .today)
        #expect(try link("https://dabble.me/entries/new") == .newEntry)
        #expect(try link("https://dabble.me/write") == .newEntry)
        #expect(try link("https://dabble.me/entries/2026/11/13") == .day(try #require(JournalDay("2026-11-13"))))
        #expect(try link("https://dabble.me/entries/2026/4/2?ref=email") == .day(try #require(JournalDay("2026-04-02"))))
        #expect(try link("https://dabble.me/search") == .search(nil))
        #expect(try link("https://dabble.me/search/") == .search(nil))
        #expect(try link("https://dabble.me/search?search%5Bterm%5D=hiking%20OR%20camping") == .search("hiking OR camping"))
        #expect(try link("https://dabble.me/search?search[term]=") == .search(nil))
        // As the web's search form writes it: "+" for a space, "%2B" for a plus.
        #expect(try link("https://dabble.me/search?search%5Bterm%5D=hiking+OR+camping") == .search("hiking OR camping"))
        #expect(try link("https://dabble.me/search?search%5Bterm%5D=C%2B%2B+notes") == .search("C++ notes"))
        #expect(try link("https://dabble.me/rewind") == .stats)
        #expect(try link("https://dabble.me/rewind/") == .stats)
        #expect(try link("https://dabble.me/rewind/2026") == .stats)
        #expect(try link("https://dabble.me/rewind/2026/share") == nil)
        #expect(try link("https://dabble.me/entries/2026") == nil)
        #expect(try link("https://dabble.me/entries/export") == nil)
        #expect(try link("https://dabble.me/settings") == nil)
        #expect(try link("https://example.com/today") == nil)
        #expect(try link("https://dabble.me/entries/2026/13/40") == nil)
    }
}

struct NewHashtagSuggestionTests {
    /// A writer with no hashtags yet: the people named first, then topics, five at most, none
    /// twice and none that's in the entry already.
    @MainActor @Test func namesComeFirstThenTopics() {
        #expect(JournalIntelligence.newSuggestions(people: ["Maya", "Sam"], topics: ["climbing", "kids", "maya", "school", "gym"], already: ["kids"])
                == ["Maya", "Sam", "climbing", "school", "gym"])
        // A crowd leaves room for a couple of topics.
        #expect(JournalIntelligence.newSuggestions(people: ["Ann", "Bo", "Cy", "Di", "Ed", "Flo"], topics: ["party", "birthday", "cake"], already: [])
                == ["Ann", "Bo", "Cy", "party", "birthday"])
        #expect(JournalIntelligence.newSuggestions(people: [], topics: ["a", "b", "c", "d", "e", "f"], already: []) == ["a", "b", "c", "d", "e"])
    }
}

struct WritingQuestionTests {
    /// The composer's placeholder: today, yesterday, or the day by name (its year when not this one).
    @Test func asksAboutTheDayBeingWritten() throws {
        let today = try #require(JournalDay("2026-11-14"))
        func question(_ iso: String) throws -> String { try #require(JournalDay(iso)).writingQuestion(today: today) }
        #expect(try question("2026-11-14") == "How has today been?")
        #expect(try question("2026-11-13") == "How was yesterday?")
        #expect(try question("2026-11-03") == "How was Tuesday, November 3?")
        #expect(try question("2025-11-03") == "How was Monday, November 3, 2025?")
    }
}

struct ShareCardTests {
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
        // An older server: no in-app purchase, so nothing is offered.
        #expect(me.appleAccountToken == nil)
        #expect(me.isProThroughApple == false)
    }

    /// Settings → Name sends only the names it changed (PATCH /api/v1/me), and an emptied one as "".
    @Test func encodesNameUpdate() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let first = try JSONSerialization.jsonObject(with: encoder.encode(NameUpdate(firstName: "Sam"))) as? [String: String]
        #expect(first == ["first_name": "Sam"])
        let cleared = try JSONSerialization.jsonObject(with: encoder.encode(NameUpdate(lastName: ""))) as? [String: String]
        #expect(cleared == ["last_name": ""])

        let json = """
        {"id":1,"email":"a@b.c","first_name":"Sam","last_name":"Rivera","name":"Sam Rivera","plan":"free","is_pro":false,
        "timezone":null,"today":"2026-11-07","entry_count":3,"can_write":true,"can_add_photos":false,"can_edit":false,
        "can_search":false,"settings_url":"https://dabble.me/settings","security_url":"https://dabble.me/security","ai_connectors":null}
        """
        #expect(try APIClient.decoder.decode(Me.self, from: Data(json.utf8)).lastName == "Rivera")
    }

    /// What build 116's server adds for in-app purchase (Api::V1::AppleSubscriptionsController.status_json).
    @Test func decodesMeWithAppleSubscription() throws {
        let json = """
        {"id":1,"email":"a@b.c","first_name":null,"plan":"pro","is_pro":true,"timezone":null,
        "today":"2026-11-07","entry_count":3,"can_write":true,"can_add_photos":true,"can_edit":true,"can_search":true,
        "settings_url":"https://dabble.me/settings","security_url":"https://dabble.me/security","ai_connectors":null,
        "apple_account_token":"6f1c0c5e-3d5b-4b7a-9a43-2f0d1c3e9b11","pro_source":"apple",
        "apple_subscription":{"product_id":"me.dabble.ios.pro.yearly","expires_at":"2027-11-07T20:00:00Z",
        "will_renew":true,"in_grace_period":false,"sandbox":true}}
        """
        let me = try APIClient.decoder.decode(Me.self, from: Data(json.utf8))
        #expect(UUID(uuidString: try #require(me.appleAccountToken)) != nil)
        #expect(me.isProThroughApple)
        #expect(!me.isProThroughWeb)
        #expect(me.appleSubscription?.productId == SubscriptionStore.yearlyID)
        #expect(me.appleSubscription?.willRenew == true)
        #expect(me.sellsInApp) // No can_buy_in_app (build 114's first servers): selling is on.

        let closing = json.replacingOccurrences(of: #""pro_source":"apple","#, with: #""pro_source":"apple","can_buy_in_app":false,"#)
        #expect(try !APIClient.decoder.decode(Me.self, from: Data(closing.utf8)).sellsInApp)
    }

    /// Settings → Plan for an account that pays on dabble.me (Api::V1::PlansController).
    @Test func decodesPlanWithWebRenewal() throws {
        let json = """
        {"plan":"pro","is_pro":true,"pro_source":"web","apple_subscription":null,
        "web_subscription":{"provider":"Stripe","expires_at":"2026-12-21T18:00:00Z","will_renew":false}}
        """
        let plan = try APIClient.decoder.decode(PlanDetails.self, from: Data(json.utf8))
        #expect(plan.webSubscription?.expiresAt == "2026-12-21T18:00:00Z")
        #expect(plan.webSubscription?.willRenew == false)
        let none = try APIClient.decoder.decode(PlanDetails.self, from: Data(#"{"plan":"free","web_subscription":null}"#.utf8))
        #expect(none.webSubscription == nil)
    }

    /// The server only accepts these (AppStore::PRODUCT_IDS); App Store Connect must use them too.
    @Test func sellsTheProductsTheServerAccepts() {
        #expect(SubscriptionStore.productIDs == ["me.dabble.ios.pro.monthly", "me.dabble.ios.pro.yearly"])
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
    @Test func aPreviewShowsADividerAsTheFullEntryDoesAndListLinesAsBullets() {
        let text = "Proud dad.\n\n* * *\n\nDoes email still work?\n- eggs\n* plates\n---\n*starred* words\n- -"
        #expect(RichText.previewLines(text)
            == "Proud dad.\n\n⸻\n\nDoes email still work?\n• eggs\n• plates\n⸻\n*starred* words\n• -")
    }

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

struct WidgetRotationTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: hour, minute: minute))!
    }

    /// Several entries share 6 AM to midnight equally; the first also has the small hours.
    @Test func entriesTakeTurnsThroughTheDay() {
        func turn(_ count: Int, _ hour: Int, _ minute: Int = 0) -> Int {
            WidgetSnapshot.rotationIndex(count: count, at: at(hour, minute), calendar: calendar)
        }
        // Four: 4.5 hours each, from 6:00, 10:30, 15:00 and 19:30.
        #expect(turn(4, 0) == 0)
        #expect(turn(4, 5, 59) == 0)
        #expect(turn(4, 10, 29) == 0)
        #expect(turn(4, 10, 30) == 1)
        #expect(turn(4, 15) == 2)
        #expect(turn(4, 19, 30) == 3)
        #expect(turn(4, 23, 59) == 3)
        // Two: nine hours each. One: always it.
        #expect(turn(2, 14, 59) == 0)
        #expect(turn(2, 15) == 1)
        #expect(turn(1, 20) == 0)
        #expect(WidgetSnapshot.rotationTimes(count: 4, on: at(8), calendar: calendar) == [at(10, 30), at(15), at(19, 30)])
        #expect(WidgetSnapshot.rotationTimes(count: 1, on: at(8), calendar: calendar).isEmpty)
    }

    /// A day shows the entry whose turn it is; with just the one, that one all day.
    @Test func aDayShowsTheEntryWhoseTurnItIs() {
        var day = WidgetSnapshot.Day(day: "2026-11-18", memories: 2, entryTitle: "1 year ago · 2025", entryText: "Snow.", entryID: 7)
        #expect(day.shown(at: at(20), calendar: calendar)?.id == 7)
        day.rotation = [.init(title: "1 year ago · 2025", text: "Snow.", id: 7), .init(title: "3 years ago · 2023", text: "Rain.", id: 9)]
        #expect(day.shown(at: at(9), calendar: calendar)?.id == 7)
        #expect(day.shown(at: at(20), calendar: calendar) == WidgetSnapshot.Shown(title: "3 years ago · 2023", text: "Rain.", id: 9))
        // No entry to show (a count alone): nothing.
        #expect(WidgetSnapshot.Day(day: "2026-11-18", memories: 2).shown(at: at(9), calendar: calendar) == nil)
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

    /// The days after the snapshot's own have the look back the app left for each: the widget
    /// keeps showing Rewind without the app being opened that day. Its own day goes by its own
    /// fields until the days have been planned, and by the plan from then on.
    @Test func daysHaveTheirPlannedLookBack() {
        var saved = snapshot(day: "2026-11-08", wrote: true, count: 36, memories: 2)
        saved.upcoming = [.init(day: "2026-11-09", memories: 3), .init(day: "2026-11-10", memoryNote: "You have a memory from 36 days ago.")]
        #expect(saved.rewind(on: date(8), calendar: calendar).known == false) // its own day: the snapshot itself
        #expect(saved.rewind(on: date(9), calendar: calendar).day?.memories == 3)
        #expect(saved.rewind(on: date(10), calendar: calendar).day?.memoryNote == "You have a memory from 36 days ago.")
        #expect(saved.rewind(on: date(11), calendar: calendar).known == false)

        // Planned (the reminders' picks, today's included): the plan says, even when it's "none".
        saved.plannedThrough = "2026-11-21"
        saved.upcoming = [.init(day: "2026-11-08", memories: 1), .init(day: "2026-11-09", memories: 3)]
        #expect(saved.rewind(on: date(8), calendar: calendar).day?.memories == 1)
        #expect(saved.rewind(on: date(11), calendar: calendar).known && saved.rewind(on: date(11), calendar: calendar).day == nil)
        // Nothing to look back on: nothing planned on any day it reaches.
        saved.upcoming = nil
        #expect(saved.rewind(on: date(8), calendar: calendar).known && saved.rewind(on: date(8), calendar: calendar).day == nil)
        // Past where the plan reached (the app not opened in weeks): not known, so the widget
        // goes by what the snapshot itself says rather than by an empty plan.
        #expect(saved.rewind(on: date(22), calendar: calendar).known == false)
    }

    /// The widget's row of the last five days: each written or not, today's last, and moving on
    /// a day at midnight without the app being opened.
    @Test func theLastFiveDaysMoveOnWithTheDate() {
        var saved = snapshot(day: "2026-11-08", wrote: true, count: 36)
        #expect(saved.lastFiveDays(on: date(8), calendar: calendar) == nil) // an older build's snapshot
        saved.writtenDays = ["2026-11-03", "2026-11-05", "2026-11-06", "2026-11-08"]
        #expect(saved.lastFiveDays(on: date(8), calendar: calendar) == [false, true, true, false, true])
        // The next day, unopened: yesterday's still there, today's not written yet.
        #expect(saved.lastFiveDays(on: date(9), calendar: calendar) == [true, true, false, true, false])
        // Today's goes by what the snapshot says of today.
        saved.wroteToday = false
        #expect(saved.lastFiveDays(on: date(8), calendar: calendar)?.last == false)
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
struct EditorPasteTests {
    /// Only one web address, alone, links the selection it's pasted over.
    @Test func aPastedAddressIsOneWebAddressAndNothingElse() {
        #expect(EditorTextView.address(from: " https://example.com/a?b=1\n")?.absoluteString == "https://example.com/a?b=1")
        #expect(EditorTextView.address(from: "see https://example.com") == nil)
        #expect(EditorTextView.address(from: "example.com") == nil)
        #expect(EditorTextView.address(from: "mailto:a@example.com") == nil)
        #expect(EditorTextView.address(from: nil) == nil)
    }
}

struct ThumbnailTests {
    /// A photo's address is asked for at the size it's shown, whatever options it came with;
    /// one that isn't through the resizer is left as it is.
    @Test func thumbnailsAskForASmallerCopy() {
        let full = "https://dabble.me/cdn-cgi/image/quality=100/https://cdn.example/uploads/a/2026-11-12/photo.jpg"
        #expect(EntrySummary.thumbnailURL(full, width: 96)?.absoluteString
            == "https://dabble.me/cdn-cgi/image/width=96,quality=85,fit=cover/https://cdn.example/uploads/a/2026-11-12/photo.jpg")
        #expect(EntrySummary.thumbnailURL("https://dabble.me/cdn-cgi/image/quality=95/https://cdn.example/p.jpg", width: 400)?.absoluteString
            == "https://dabble.me/cdn-cgi/image/width=400,quality=85,fit=cover/https://cdn.example/p.jpg")
        #expect(EntrySummary.thumbnailURL("https://cdn.example/p.jpg", width: 96)?.absoluteString == "https://cdn.example/p.jpg")
        #expect(EntrySummary.thumbnailURL(nil, width: 96) == nil)
    }
}

struct SpotifyPlayerTests {
    /// An entry's player shows its song without starting it; a tap on a song is what plays.
    @Test func thePlayerOnlyStartsWhenAsked() {
        let shown = SpotifyPlayer.page(for: "abc123", autoplay: false)
        let played = SpotifyPlayer.page(for: "abc123", autoplay: true)
        #expect(shown.contains("spotify:track:abc123") && shown.contains("var wants = false"))
        #expect(played.contains("var wants = true"))
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

    private var year: Rewind { rewind() }

    private func rewind(year: Int = 2026, quietDay: String = "Quiet Saturday at home.") -> Rewind {
        let song = Song(title: "Holocene", artists: ["Bon Iver"], spotifyUrl: URL(string: "https://open.spotify.com/track/abc")!)
        return Rewind.build(year: year, summaries: [
            summary(1, "2026-01-03", "Leo and Silas built a fort. **Great** day. #Leo", tags: ["Leo"]),
            summary(2, "2026-01-10", "Leo lost a tooth in Denver. https://open.spotify.com/track/abc", songs: [song]),
            summary(3, "2026-03-07", "Flew to Lisbon with Katelyn. I felt lucky to be there with her.", image: "https://x.test/a.jpg"),
            summary(4, "2026-03-14", "Then Silas rode a bike while Alex cheered. #bikes #Leo", tags: ["bikes", "Leo"]),
            summary(5, "2026-03-21", quietDay, songs: [song]),
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

    /// The story Apple Intelligence wrote is kept until an entry changes, even by an edit that
    /// leaves the count of words and the people as they were.
    @Test func aSavedStoryIsDroppedWhenAnEntryIsEdited() {
        let written = rewind()
        defer { UserDefaults.standard.removeObject(forKey: "rewind.story.2026") }
        RewindStory(line: "Quiet Saturday at home.", lineDay: "2026-03-21").save(for: written)
        #expect(RewindStory.saved(for: rewind())?.line == "Quiet Saturday at home.")
        let edited = rewind(quietDay: "Rainy Saturday at home.")
        #expect(edited.wordCount == written.wordCount && edited.people == written.people)
        #expect(RewindStory.saved(for: edited) == nil)
    }

    @Test func theSeasonIsNovemberToJanuary() throws {
        #expect(RewindSeason.year(on: try #require(JournalDay("2026-11-01"))) == 2026)
        #expect(RewindSeason.year(on: try #require(JournalDay("2026-12-31"))) == 2026)
        #expect(RewindSeason.year(on: try #require(JournalDay("2027-01-15"))) == 2026)
        #expect(RewindSeason.year(on: try #require(JournalDay("2027-02-01"))) == nil)
        #expect(RewindSeason.year(on: try #require(JournalDay("2026-10-31"))) == nil)
        // Today's corner names it for a month around the new year.
        for (day, named) in [("2026-12-14", false), ("2026-12-15", true), ("2027-01-01", true), ("2027-01-15", true), ("2027-01-16", false), ("2026-11-20", false)] {
            #expect(RewindSeason.isHeadline(on: try #require(JournalDay(day))) == named)
        }
    }
}

@MainActor
struct EntryTemplateTests {
    /// The template is kept as it was typed: its formatting, and the blank lines and empty
    /// list items that are where the writing goes. An emptied one is no template at all.
    @Test func theTemplateIsKeptAsTyped() {
        defer { EntryTemplate.clear() }
        EntryTemplate.clear()
        #expect(EntryTemplate.runs.isEmpty)
        let template = [DocumentRun("One Win", bold: true), DocumentRun("\n• \n"), DocumentRun("One Bit of Gratitude", bold: true), DocumentRun("\n\n")]
        EntryTemplate.runs = template
        #expect(EntryTemplate.runs == template)
        // Through the editor's text and back, nothing's lost.
        let text = RichText.attributedString(typed: template, style: .journal)
        #expect(text.string == "One Win\n• \nOne Bit of Gratitude\n\n")
        #expect(RichText.typedRuns(from: text) == template)
        // Writing starts at the first empty item.
        #expect(RichText.firstBlank(in: text.string) == ("One Win\n• " as NSString).length)
        #expect(RichText.firstBlank(in: "No room here") == nil)
        EntryTemplate.runs = []
        #expect(UserDefaults.standard.data(forKey: EntryTemplate.runsKey) == nil)
    }

    /// The empty page's preview of the template keeps its words and formatting, but not the blank lines
    /// and empty items left for writing.
    @Test func todaysPreviewSkipsTheRoomToWrite() {
        let template = [DocumentRun("One Win", bold: true), DocumentRun("\n\n• \n"), DocumentRun("One Point of Tension", bold: true), DocumentRun("\n1. \n\n"), DocumentRun("Grateful for "), DocumentRun("one thing", italic: true)]
        let preview = EntryTemplate.preview(template)
        #expect(String(preview.characters) == "One Win\nOne Point of Tension\nGrateful for one thing")
        let win = preview.runs.first { String(preview[$0.range].characters) == "One Win" }
        #expect(win?.inlinePresentationIntent == .stronglyEmphasized)
        #expect(EntryTemplate.preview([DocumentRun("\n• \n\n")]).characters.isEmpty)
        // Figures of the writer's own are words, not a list's marker.
        #expect(String(EntryTemplate.preview([DocumentRun("Mood 1-10\n2025\n12. \n")]).characters) == "Mood 1-10\n2025")
    }

    /// A draft is kept as typed too: a link in it keeps where it goes.
    @Test func typedTextKeepsItsLinks() {
        let typed = [DocumentRun("See "), DocumentRun("the trail", link: "https://example.com/trail"), DocumentRun(" soon")]
        let text = RichText.attributedString(typed: typed, style: .journal)
        #expect(RichText.typedRuns(from: text) == typed)
        #expect(RichText.blocks(from: text) == [DocumentBlock(type: .paragraph, runs: typed)])
    }

    /// A template kept by an earlier build (as an entry's blocks) still reads.
    @Test func anEarlierBuildsTemplateStillReads() throws {
        defer { EntryTemplate.clear() }
        EntryTemplate.clear()
        let blocks: [DocumentBlock] = [.paragraph(DocumentRun("Grateful for", bold: true)), DocumentBlock(type: .bullet, runs: [DocumentRun("One thing")])]
        UserDefaults.standard.set(try JSONEncoder().encode(blocks), forKey: EntryTemplate.blocksKey)
        #expect(EntryTemplate.runs.map(\.text).joined() == "Grateful for\n• One thing")
    }
}

struct ShareTextTests {
    /// Share hands over the entry's date and its words; an entry with no words has none to share.
    @Test func sharesTheDateThenTheWords() {
        #expect(EntryActionsSheet.sharedText(date: "Monday, November 16, 2026", body: "A slow evening.\n") == "Monday, November 16, 2026\n\nA slow evening.")
        #expect(EntryActionsSheet.sharedText(date: "Monday, November 16, 2026", body: "  \n") == nil)
    }
}

struct ReadingTextSizeTests {
    /// Five stops, the default in the middle at 99%, each larger than the one before.
    @Test func theDefaultIsTheMiddleStop() {
        let sizes = ReadingTextSize.allCases
        #expect(sizes.count == 5 && sizes[2] == .standard)
        #expect(sizes.map(\.scale) == [0.90, 0.95, 0.99, 1.05, 1.10])
        #expect(sizes.map(\.label) == ["Smallest", "Smaller", "Default", "Larger", "Largest"])
    }

    /// A size chosen on the old scale lands on the nearest new stop, once.
    @Test func anOldChoiceIsCarriedOver() throws {
        #expect(ReadingTextSize.migrated(fromLegacy: 0) == .smallest)  // Small, 92% → 90%
        #expect(ReadingTextSize.migrated(fromLegacy: 1) == .standard)  // Default, 100% → 99%
        #expect(ReadingTextSize.migrated(fromLegacy: 2) == .largest)   // Large, 108% → 110%
        #expect(ReadingTextSize.migrated(fromLegacy: 3) == .largest)   // Extra Large, 116% → 110%
        #expect(ReadingTextSize.migrated(fromLegacy: 4) == .largest)   // Largest, 124% → 110%
        #expect(ReadingTextSize.migrated(fromLegacy: 9) == .standard)  // not a size at all

        let name = "ReadingTextSizeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        // Never chosen: nothing's written, so the new default applies.
        ReadingTextSize.migrateStoredSize(in: defaults)
        #expect(defaults.object(forKey: ReadingTextSize.storageKey) == nil)
        defaults.set(2, forKey: ReadingTextSize.legacyStorageKey)
        ReadingTextSize.migrateStoredSize(in: defaults)
        #expect(defaults.integer(forKey: ReadingTextSize.storageKey) == ReadingTextSize.largest.rawValue)
        // A choice made since isn't overwritten.
        defaults.set(ReadingTextSize.smallest.rawValue, forKey: ReadingTextSize.storageKey)
        ReadingTextSize.migrateStoredSize(in: defaults)
        #expect(defaults.integer(forKey: ReadingTextSize.storageKey) == ReadingTextSize.smallest.rawValue)
    }
}

struct WhatToTestNotesTests {
    /// TestFlight cuts a build's "What to Test" off at 4,000 characters (Xcode Cloud warns, and
    /// the end is lost): the notes are rewritten for each build, not added to.
    @Test func theNotesFitTestFlight() throws {
        let notes = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "TestFlight/WhatToTest.en-US.txt")
        let text = try String(contentsOf: notes, encoding: .utf8)
        #expect(text.count <= 4000, "WhatToTest.en-US.txt is \(text.count) characters: rewrite it for this build")
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

/// The Journal list's paragraph gap matches the entry page's: a blank line set in this size,
/// plus the line spacing, is 0.6 of the text size.
struct ParagraphGapTests {
    @Test func gapLineAndSpacingMakeTheEntryPagesParagraphSpacing() {
        for (size, spacing) in [(CGFloat(17), CGFloat(5)), (16.83, 4.95), (18.7, 5.5)] {
            let gapSize = TimelineEntryRow.paragraphGapFontSize(fontSize: size, lineSpacing: spacing)
            let base = UIFont.systemFont(ofSize: gapSize)
            let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: gapSize) } ?? base
            #expect(abs(font.lineHeight + spacing - (size * 0.6).rounded()) < 0.5)
        }
    }

    @Test func neverBelowOnePoint() {
        #expect(TimelineEntryRow.paragraphGapFontSize(fontSize: 10, lineSpacing: 20) == 1)
    }
}

/// A draft keeps its photos: written once each, read back in order, pruned and cleared with it.
struct DraftPhotoTests {
    private func photo(_ byte: UInt8) -> PreparedPhoto {
        PreparedPhoto(data: Data([byte, byte, byte]), contentType: "image/jpeg", filename: "photo.jpg", thumbnail: Data([byte]))
    }

    @Test func photosRoundTripInOrderAndArePrunedAndCleared() {
        let key = "test-\(UUID().uuidString)"
        defer { DraftStore.clear(key) }
        DraftStore.savePhotos([("a", photo(1)), ("b", photo(2))], key: key)
        let loaded = DraftStore.loadPhotos(["b", "a"], key: key)
        #expect(loaded.map(\.name) == ["b", "a"])
        #expect(loaded.map(\.photo) == [photo(2), photo(1)])

        DraftStore.savePhotos([("b", photo(2))], key: key)
        #expect(DraftStore.loadPhotos(["a", "b"], key: key).map(\.name) == ["b"])

        DraftStore.clear(key)
        #expect(DraftStore.loadPhotos(["b"], key: key).isEmpty)
    }

    @Test func draftsWithoutPhotosStillDecode() throws {
        let old = #"{"blocks":[],"savedAt":0}"#
        let draft = try JSONDecoder().decode(DraftStore.Draft.self, from: Data(old.utf8))
        #expect(draft.photos == nil)
        #expect(draft.removesPhoto == nil)
    }
}

/// Speaking an entry: what's heard goes in at the cursor as if typed there.
@MainActor
struct DictationTests {
    @Test func spokenWordsAreSpacedLikeTypedOnes() {
        #expect(Dictation.insertion(of: "Today I walked.", before: "") == "Today I walked.")
        #expect(Dictation.insertion(of: " It was quiet. ", before: "A long day.") == " It was quiet.")
        #expect(Dictation.insertion(of: " It was quiet.", before: "A long day. ") == "It was quiet.")
        #expect(Dictation.insertion(of: "  \n", before: "A long day.") == "")
    }

    /// Mid-sentence, a dictionary word starts in lowercase; "I", names and acronyms don't.
    @Test func midSentenceWordsStartInLowercase() {
        #expect(Dictation.insertion(of: "Then we left.", before: "We ate and") == " then we left.")
        #expect(Dictation.insertion(of: "I left early.", before: "After dinner") == " I left early.")
        #expect(Dictation.insertion(of: "NASA called.", before: "Then") == " NASA called.")
        #expect(Dictation.insertion(of: "Then we left.", before: "We ate:") == " Then we left.")
    }

    @Test func hashtagsBecomeWordsToExpect() {
        #expect(Dictation.hints(from: ["#Leo", "leo", "Kenji", " ", "#"]) == ["Leo", "Kenji"])
        #expect(Dictation.hints(from: (1...150).map { "tag\($0)" }).count == Dictation.maxHints)
    }

    /// Custom Vocabulary comes first, so a long list of hashtags never pushes a word out, and
    /// Settings lists only the hashtags that fit, without the writer's own words.
    @Test func customVocabularyComesBeforeHashtags() {
        let words = ["Ouray", "Dabble Me"]
        let all = ["#ouray"] + (1...150).map { "tag\($0)" }
        let expected = Dictation.expected(words: words, recentTags: ["Leo"], allTags: all)
        #expect(Array(expected.prefix(3)) == ["Ouray", "Dabble Me", "Leo"])
        #expect(expected.count == Dictation.maxHints)
        let terms = Dictation.hashtagTerms(words: words, recentTags: ["Leo"], allTags: all)
        #expect(terms.first == "Leo")
        #expect(!terms.contains { $0.lowercased() == "ouray" })
        #expect(terms.count == Dictation.maxHints - words.count)
    }
}

/// Hex's cleanup model, from the app's bundle: spoken corrections and ums go, the rest stays.
struct CleanupTaggerTests {
    @Test func spokenCorrectionsAndFillersGo() throws {
        let tagger = CleanupTagger()
        #expect(try tagger.clean("Let's ship it Tuesday, no wait, Thursday.") == "Let's ship it Thursday.")
        #expect(try tagger.clean("Can you send it to John, I mean Mike?") == "Can you send it to Mike?")
        #expect(try tagger.clean("Test one two three.") == "Test one two three.")
        #expect(tagger.isLoaded)
    }

    @Test func aLateCleanupKeepsWhatWasSaid() async {
        let tagger = CleanupTagger()
        let spoken = "Can you send it to John, I mean Mike?"
        #expect(await tagger.clean(spoken, within: 0) == spoken)
        #expect(await tagger.clean(spoken, within: 5) == "Can you send it to Mike?")
    }
}

/// Settings → Dictation's words to expect: each once, trimmed, removable.
struct DictationSettingsTests {
    @Test func wordsAreAddedOnceAndRemoved() {
        var stored = DictationSettings.adding(" Kenji ", to: "")
        stored = DictationSettings.adding("kenji", to: stored)
        stored = DictationSettings.adding("Ouray", to: stored)
        stored = DictationSettings.adding("  ", to: stored)
        #expect(DictationSettings.words(from: stored) == ["Kenji", "Ouray"])
        #expect(DictationSettings.words(from: DictationSettings.removing("Kenji", from: stored)) == ["Ouray"])
    }

    /// The cleanup model only knows English.
    @Test func onlyEnglishIsCleanedUp() {
        #expect(DictationSettings.cleansUp(Locale(identifier: "en-US")))
        #expect(DictationSettings.cleansUp(Locale(identifier: "en-GB")))
        #expect(!DictationSettings.cleansUp(Locale(identifier: "es-MX")))
    }
}

/// Apple Intelligence's fixes are kept only when they still look like what was said.
struct TranscriptCleanupGuardTests {
    @Test func aFixedWordIsKeptARewriteIsNot() {
        let said = "We went to the beach and I got sun bird on my shoulders."
        #expect(TranscriptCleanupGuard.isAcceptable(original: said, cleaned: "We went to the beach and I got sunburnt on my shoulders."))
        #expect(!TranscriptCleanupGuard.isAcceptable(original: said, cleaned: "We didn't go to the beach and I got sunburnt on my shoulders."))
        #expect(!TranscriptCleanupGuard.isAcceptable(original: "We left at 6.", cleaned: "We left at 7."))
        #expect(!TranscriptCleanupGuard.isAcceptable(original: said, cleaned: "A sunny beach day left my shoulders burnt, which taught me to bring sunscreen next time for sure."))
    }

    /// A question in an entry stays the question; the model never answers it or adds a preamble.
    @Test func neverAnAnswerOrAPreamble() {
        #expect(!TranscriptCleanupGuard.isAcceptable(original: "should I call my sister tonight or wait until sunday",
                                                     cleaned: "Yes, you should call your sister tonight."))
        #expect(!TranscriptCleanupGuard.isAcceptable(original: "would you say", cleaned: "Yes, I would say."))
        #expect(!TranscriptCleanupGuard.isAcceptable(original: "the report needs a short summary before the meeting on monday",
                                                     cleaned: "Sure, I can help with that. Here's the cleaned transcript: The report needs a short summary before the meeting on Monday."))
        #expect(!TranscriptCleanupGuard.isAcceptable(original: "bring these to the meeting", cleaned: "Bring these: notes."))
        #expect(!TranscriptCleanupGuard.isAcceptable(original: "i will call you tomorrow", cleaned: "I will definitely call you tomorrow."))
    }

    @Test func aSelfCorrectionOrStutterMayShortenIt() {
        #expect(TranscriptCleanupGuard.isAcceptable(original: "i'll send it tomorrow, i mean, i'll send it today", cleaned: "I'll send it today."))
        #expect(TranscriptCleanupGuard.isAcceptable(original: "send it on tuesday actually wednesday", cleaned: "Send it on Wednesday."))
        #expect(TranscriptCleanupGuard.isAcceptable(original: "i i think we should go", cleaned: "I think we should go."))
        #expect(TranscriptCleanupGuard.isAcceptable(original: "i am going home", cleaned: "I'm going home."))
        // Without a correction, cutting most of it off is refused.
        #expect(!TranscriptCleanupGuard.isAcceptable(original: "we drove to the coast and walked on the beach until the sun went down",
                                                     cleaned: "We drove to the coast."))
    }
}

/// "Moments from your iPhone" (Journaling Suggestions): what a picked moment adds to an entry.
struct MomentTextTests {
    private let us = Locale(identifier: "en_US")

    @Test func aLineForEachThingInTheOrderADayIsRemembered() {
        var moment = Moment(title: "Morning in Golden Gate Park")
        moment.places = [.init(place: "Golden Gate Park", city: "San Francisco")]
        moment.workouts = [.init(name: "Outdoor Walk", meters: 5_230, seconds: 3_720)]
        moment.steps = 8_214
        moment.people = ["Sam", "Alex"]
        moment.songs = [.init(title: "Bloom", by: "The Paper Kites")]
        moment.podcasts = [.init(title: "Episode 12", by: nil)]
        moment.feelings = ["Pleasant"]
        #expect(moment.heading == "Morning in Golden Gate Park")
        #expect(moment.lines(locale: us) == [
            "📍 Golden Gate Park, San Francisco",
            "🏃 Outdoor Walk · 3.2 mi · 1 hr, 2 min",
            "👣 8,214 steps",
            "👥 With Sam and Alex",
            "🎶 The Paper Kites – Bloom",
            "🎧 Episode 12",
            "💭 Felt pleasant"
        ])
    }

    @Test func repeatsAndBlanksGoInOnce() {
        var moment = Moment(title: "  ")
        // A place offered both on its own and in a group, a city that's also the place's name,
        // a workout with nothing to say but that it happened.
        moment.places = [.init(place: "Home", city: "Denver"), .init(place: "Home", city: "Denver"), .init(place: "Denver", city: "Denver"), .init(place: " ", city: nil)]
        moment.workouts = [.init(name: nil, meters: 0, seconds: 30)]
        moment.songs = [.init(title: "", by: " ")]
        #expect(moment.heading == nil)
        #expect(moment.lines(locale: us) == ["📍 Home, Denver", "📍 Denver", "🏃 Workout"])
    }

    @Test func aReflectionGoesInWithoutItsKind() {
        var moment = Moment(title: "Creativity Reflection")
        moment.reflections = ["What did you make this week that you're proud of?"]
        #expect(moment.heading == nil)
        #expect(moment.lines().isEmpty)
    }

    @Test func aMomentFromAnotherDayIsAskedAbout() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Denver"))
        func at(_ day: Int, _ hour: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)))
        }
        var moment = Moment(title: "Walk")
        // No date: nothing to ask.
        #expect(moment.day(otherThan: try at(22, 9), calendar: calendar) == nil)
        // An afternoon on the 18th, written about on the 18th and on the 22nd.
        moment.when = DateInterval(start: try at(18, 14), end: try at(18, 15))
        #expect(moment.day(otherThan: try at(18, 21), calendar: calendar) == nil)
        #expect(moment.day(otherThan: try at(22, 9), calendar: calendar) == calendar.startOfDay(for: try at(18, 0)))
        // A trip from the 18th to the 20th, ending at midnight: any of those days, not the 21st.
        moment.when = DateInterval(start: try at(18, 8), end: try at(21, 0))
        #expect(moment.day(otherThan: try at(20, 12), calendar: calendar) == nil)
        #expect(moment.day(otherThan: try at(21, 12), calendar: calendar) == calendar.startOfDay(for: try at(18, 0)))
    }

    @Test func nothingToSayAddsNothing() {
        #expect(Moment(title: "").lines().isEmpty)
    }
}

struct PasskeyPromptTests {
    private func defaults() -> UserDefaults {
        let name = "PasskeyPromptTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func asksOnlyAfterASignInToAnAccountWithoutAPasskey() {
        let store = defaults()
        #expect(PasskeyPrompt.shouldAsk(hasPasskey: false, justSignedIn: true, defaults: store))
        // Not on launch, and not once there's a passkey.
        #expect(!PasskeyPrompt.shouldAsk(hasPasskey: false, justSignedIn: false, defaults: store))
        #expect(!PasskeyPrompt.shouldAsk(hasPasskey: true, justSignedIn: true, defaults: store))
        // An older server doesn't say: don't ask.
        #expect(!PasskeyPrompt.shouldAsk(hasPasskey: nil, justSignedIn: true, defaults: store))
    }

    @Test func notNowPutsItOffForThirtyDays() {
        let store = defaults()
        let now = Date()
        PasskeyPrompt.dismiss(now: now, defaults: store)
        #expect(!PasskeyPrompt.shouldAsk(hasPasskey: false, justSignedIn: true, now: now.addingTimeInterval(86_400), defaults: store))
        let later = now.addingTimeInterval(TimeInterval(PasskeyPrompt.snoozeDays + 1) * 86_400)
        #expect(PasskeyPrompt.shouldAsk(hasPasskey: false, justSignedIn: true, now: later, defaults: store))
    }

    @Test func stopsAfterTheLastNotNow() {
        let store = defaults()
        let now = Date()
        for _ in 0..<PasskeyPrompt.maxAsks { PasskeyPrompt.dismiss(now: now, defaults: store) }
        let later = now.addingTimeInterval(365 * 86_400)
        #expect(!PasskeyPrompt.shouldAsk(hasPasskey: false, justSignedIn: false, now: later, defaults: store))
        #expect(!PasskeyPrompt.shouldAsk(hasPasskey: false, justSignedIn: true, now: later, defaults: store))
    }
}

/// iOS kills the app (TCC) the first time it touches the mic, camera and so on without a usage string.
struct PrivacyUsageTests {
    @Test func everyPermissionWeAskForIsExplained() {
        let info = Bundle.main.infoDictionary ?? [:]
        for key in [
            "NSMicrophoneUsageDescription",
            "NSSpeechRecognitionUsageDescription",
            "NSCameraUsageDescription",
            "NSPhotoLibraryAddUsageDescription",
            "NSCalendarsFullAccessUsageDescription",
            "NSFaceIDUsageDescription",
        ] {
            let text = info[key] as? String ?? ""
            #expect(!text.isEmpty, "Info.plist is missing \(key)")
        }
    }
}
