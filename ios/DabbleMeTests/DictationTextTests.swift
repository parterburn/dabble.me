import Testing
@testable import DabbleMe

// Cases from Hex's own tests (github.com/anomalyco/hex, ios/HEXMobileTests), MIT License.

/// Custom Vocabulary and name-like hashtags keep the writer's spelling, and only whole words change.
struct VocabularySpellingTests {
    @Test func theWritersSpellingWins() {
        #expect(VocabularySpelling.apply(["Claude", "OpenCode"], to: "i use claude in open code.") == "i use Claude in OpenCode.")
        #expect(VocabularySpelling.apply(["OpenCode"], to: "Open-Code is great") == "OpenCode is great")
        #expect(VocabularySpelling.apply(["OpenCode"], to: "open, code") == "open, code")
        #expect(VocabularySpelling.apply(["Hex"], to: "hexagon") == "hexagon")
        #expect(VocabularySpelling.apply(["Hex"], to: "hex") == "Hex")
        #expect(VocabularySpelling.apply(["Claude"], to: "claude's idea") == "Claude's idea")
        #expect(VocabularySpelling.apply(["Claude"], to: "claude’s idea") == "Claude’s idea")
        #expect(VocabularySpelling.apply(["Claude"], to: "a cloud") == "a cloud")
        #expect(VocabularySpelling.apply(["iPhone 17"], to: "my iphone 17 broke") == "my iPhone 17 broke")
        #expect(VocabularySpelling.apply(["iPhone 7"], to: "my iphone 7 broke") == "my iPhone 7 broke")
        #expect(VocabularySpelling.apply(["Plan B"], to: "go with plan b") == "go with Plan B")
        #expect(VocabularySpelling.apply(["Formula 1"], to: "the formula 1 race") == "the Formula 1 race")
        #expect(VocabularySpelling.apply(["X-ray"], to: "an x-ray today") == "an X-ray today")
        #expect(VocabularySpelling.apply(["X-ray"], to: "an x ray") == "an X-ray")
        #expect(VocabularySpelling.apply(["WeChat"], to: "message me on we chat") == "message me on WeChat")
        #expect(VocabularySpelling.apply(["Open", "OpenCode"], to: "open code") == "OpenCode")
        #expect(VocabularySpelling.apply(["Ina"], to: "live in a house") == "live in a house")
        #expect(VocabularySpelling.apply(["Isa"], to: "this is a test") == "this is a test")
        #expect(VocabularySpelling.apply(["Arun"], to: "go for a run") == "go for a run")
        #expect(VocabularySpelling.apply(["Shell"], to: "she'll come") == "she'll come")
        #expect(VocabularySpelling.apply(["Well"], to: "we'll go") == "we'll go")
        #expect(VocabularySpelling.apply(["OpenCode"], to: "open\n\ncode") == "open\n\ncode")
        #expect(VocabularySpelling.apply(["Claude"], to: "'claude'") == "'Claude'")
        #expect(VocabularySpelling.apply(["Claude"], to: "‘claude’") == "‘Claude’")
        #expect(VocabularySpelling.apply(["Dabble Me"], to: "i wrote in dabble me today") == "i wrote in Dabble Me today")
        #expect(VocabularySpelling.apply(["Dabble Me"], to: "Wrote in #DabbleMe today.") == "Wrote in #DabbleMe today.")
        #expect(VocabularySpelling.apply(["Leo"], to: "#leo and leo") == "#leo and Leo")
    }
}

/// Punctuation said by name becomes the mark; the same words in a sentence stay words.
struct SpokenPunctuationTests {
    private func punctuated(_ text: String) -> String {
        SpokenPunctuation.format(text, language: "en")
    }

    @Test func namesBecomeMarks() {
        #expect(punctuated("That is amazing exclamation point.") == "That is amazing!")
        #expect(punctuated("That is amazing exclamation mark.") == "That is amazing!")
        #expect(punctuated("I came semicolon, I saw semicolon, I conquered.") == "I came; I saw; I conquered.")
        #expect(punctuated("It was good dash really good.") == "It was good – really good.")
        #expect(punctuated("It is a well hyphen known fact.") == "It is a well-known fact.")
        #expect(punctuated("She said, open quote, hello, their close quote, and left.") == "She said, “hello, their”, and left.")
        #expect(punctuated("Call me, open Paren after lunch close, Paren, please.") == "Call me, (after lunch), please.")
        #expect(punctuated("Wait for it, ellipsis.") == "Wait for it…")
        #expect(punctuated("Feeling great hashtag blessed.") == "Feeling great #blessed.")
        #expect(punctuated("Great job, Smiley.") == "Great job :-)")
        #expect(punctuated("It is John Apostrophe S Carr.") == "It is John's Carr.")
        #expect(punctuated("Open parenthesis, just getting close parenthesis.") == "(just getting).")
        #expect(punctuated("Thanks so much, exclamation point CU tomorrow period.") == "Thanks so much! CU tomorrow.")
        #expect(punctuated("Okay, comma, so here is the thing, comment, I can't make it.") == "Okay, so here is the thing, comment, I can't make it.")
        #expect(punctuated("I'll be there at noon, see you soon.") == "I'll be there at noon, see you soon.")
        #expect(punctuated("I'll be there at noon, comma, see you soon, period") == "I'll be there at noon, see you soon.")
        #expect(punctuated("Are you coming tonight question mark?") == "Are you coming tonight?")
        #expect(punctuated("Here is the plan colon we leave at noon full stop.") == "Here is the plan: we leave at noon.")
        #expect(punctuated("It is a well-hyphen known fact") == "It is a well-known fact")
        #expect(punctuated("She said open quote hello there close quote and left.") == "She said “hello there” and left.")
        #expect(punctuated("Open parenthesis just kidding close parenthesis.") == "(just kidding).")
        #expect(punctuated("Thanks so much exclamation point see you tomorrow period.") == "Thanks so much! See you tomorrow.")
        #expect(punctuated("Hi Sarah comma\nthanks for the update period") == "Hi Sarah,\nthanks for the update.")
        #expect(punctuated("Hi Sarah comma how are you question mark") == "Hi Sarah, how are you?")
        #expect(punctuated("I'm on my way period see you soon") == "I'm on my way. See you soon")
        #expect(punctuated("Note to self colon buy milk") == "Note to self: buy milk")
        #expect(punctuated("Dear John comma") == "Dear John,")
        #expect(punctuated("Can you send it today question mark thanks") == "Can you send it today? Thanks")
        #expect(punctuated("Meet me at 5 period") == "Meet me at 5.")
        #expect(punctuated("Who are you going with question mark") == "Who are you going with?")
        #expect(punctuated("He said open quote no way close quote period") == "He said “no way”.")
        #expect(punctuated("He said quote I'm fine unquote and left") == "He said “I'm fine” and left")
        #expect(punctuated("Hashtag throwback") == "#throwback")
        #expect(punctuated("It costs dollar sign 50") == "It costs $50")
        #expect(punctuated("Bring snacks open paren chips or pretzels close paren") == "Bring snacks (chips or pretzels)")
        #expect(punctuated("Love you smiley face") == "Love you :-)")
        #expect(punctuated("Okay comma sounds good period") == "Okay, sounds good.")
        #expect(punctuated("Thanks exclamation point exclamation point") == "Thanks!")
        #expect(punctuated("I went to the store period") == "I went to the store.")
        #expect(punctuated("We had a blast period") == "We had a blast.")
    }

    @Test func quotesAndBracketsPair() {
        #expect(punctuated("Close quote that") == "Close quote that")
        #expect(punctuated("He was fine close paren") == "He was fine close paren")
        #expect(punctuated("Can you quote me on that") == "Can you quote me on that")
        #expect(punctuated("He said \"hi end quote") == "He said \"hi\"")
    }

    @Test func marksAlreadyWrittenStay() {
        for text in [
            "That is amazing!", "Here is the plan: we leave at noon.", "I came; I saw; I conquered",
            "It was good – really good", "She said \"hello there\" and left", "Call me (after lunch) please",
            "Wait for it…", "Email me a john@gmail.com", "Feeling great. #Blessed.", "Great job :-)",
            "It is John's car", "Hi Sarah,\nThanks for the update.", "He has a? Tattoo on his arm.",
            "Thanks so much! See you tomorrow.",
        ] {
            #expect(punctuated(text) == text)
        }
    }

    @Test func proseStaysAsSaid() {
        let english = [
            "It was a long period of time.",
            "It was a stressful period.",
            "It was a stressful period, but we got through it.",
            "It's a real question mark.",
            "The comma is optional here.",
            "She put a dash of salt in the soup.",
            "He has a question mark tattoo on his arm.",
            "The colon is part of the digestive system.",
            "Put a period at the end of the sentence.",
            "I'm not sure what the hashtag is.",
            "The trial period ends tomorrow.",
            "There's a big question mark over his future.",
            "My period started this morning.",
            "We had a free period after lunch.",
            "The grace period is thirty days.",
            "Do you use the Oxford comma?",
            "She made a mad dash for the door.",
            "I watched a period drama last night.",
            "He was diagnosed with colon cancer.",
            "My dash cam caught the whole thing.",
            "Add a dash of lemon juice.",
            "The hyphen in that word is wrong.",
            "Use an apostrophe for possession.",
            "That hashtag is trending right now.",
            "What does the at sign mean in an email?",
            "He ended the call with a smiley face emoji.",
            "During that period we lived in Boston.",
            "The question mark key is broken.",
            "An exclamation point at the end feels too loud.",
            "Commas and periods go inside the quotes.",
            "Is that a comma or a period?",
            "I need a quote for the kitchen remodel.",
            "Can you quote me on that?",
            "He used air quotes around the word.",
            "The open quote was missing.",
            "It's a quote unquote expert opinion.",
            "The time period doesn't matter.",
            "He's in colon surgery right now.",
            "Every comma counts in a contract.",
            "That was the last period of the game.",
            "They scored in the third period.",
            "A semicolon joins two clauses.",
            "The ellipsis at the end looks passive aggressive.",
            "Click the dollar sign to see prices.",
            "Type the hashtag before the word.",
            "A smiley can soften a message.",
            "Draw a dash between the numbers.",
            "The comma-separated list is attached.",
            "The waiting period was annoying.",
            "Can you dash off a quick reply?",
            "We need to dash to the store.",
            "I'll dash home after work.",
            "This colon cleanse is a scam.",
            "Her period was late this month.",
            "What a period of growth for the company.",
            "The comma after Hi is optional.",
            "I love the Oxford comma debate.",
            "The quote from the plumber was too high.",
            "The ten-year period ended in June.",
            "That was a really tough period for us.",
            "It happened over a short period.",
            "The colon in the time looks wrong.",
            "Where is the question mark on this keyboard?",
            "Is there an exclamation mark in the title?",
            "My dog is called Dash.",
            "I'll text Dash later.",
            "George Smiley is a spy.",
            "We waited for a period of hours.",
            "The Jurassic period was long ago.",
            "Your period tracker sent a notification.",
            "Use a colon before a list.",
            "The dollar sign is missing.",
            "No comma needed.",
            "I used comma separated values.",
            "Period cramps are the worst.",
            "Comma placement matters.",
            "That smiley was a bit much.",
            "Leave the quote as it is.",
            "Write an exclamation point if you're excited.",
            "She's the period expert on the team.",
            "Hashtags are everywhere.",
            "Quote me if you want.",
            "He gave a quote to the press.",
            "In the past, period films were huge.",
            "Colon health is important.",
            "The first period starts at eight.",
            "Send a smiley to Mom.",
        ]

        for sentence in english {
            #expect(punctuated(sentence) == sentence)
        }
        #expect(punctuated("It costs two comma five million") == "It costs two comma five million")
        #expect(punctuated("The meeting is at 3 colon 30") == "The meeting is at 3 colon 30")
    }
}

/// What dictation does with the writer's hashtags.
struct DictationHashtagTests {
    @Test func aSpokenHashtagTakesAKnownTagsSpelling() {
        let tags = ["Leo", "LeoBirthday", "NYC"]
        #expect(Dictation.knownHashtags(in: "Cake for #leo birthday.", tags: tags) == "Cake for #LeoBirthday.")
        #expect(Dictation.knownHashtags(in: "Walked with #leo today", tags: tags) == "Walked with #Leo today")
        #expect(Dictation.knownHashtags(in: "Back in #nyc!", tags: tags) == "Back in #NYC!")
        #expect(Dictation.knownHashtags(in: "Feeling great #blessed.", tags: tags) == "Feeling great #blessed.")
        #expect(Dictation.knownHashtags(in: "No tags here", tags: tags) == "No tags here")
        // A Custom Vocabulary term with a space is no tag to write.
        #expect(Dictation.knownHashtags(in: "Wrote in #dabble me", tags: ["Dabble Me"]) == "Wrote in #dabble me")
    }

    @MainActor @Test func onlyNameLikeHashtagsAreSpellings() {
        let spellings = Dictation.spellings(from: ["dabble me", "LeoBirthday", "work", "Work", "Leo2"], vocabulary: ["dabble me"])
        #expect(spellings.contains("dabble me"))
        #expect(!spellings.contains("LeoBirthday"))
        #expect(!spellings.contains("work"))
        #expect(!spellings.contains("Work"))
        #expect(!spellings.contains("Leo2"))
    }
}

/// A name the transcriber spelled its own way takes the writer's spelling, by sound, and only
/// a name: capitalized, not a dictionary word, sounding like exactly one of theirs.
struct SoundAlikeNamesTests {
    private let ordinary: Set<String> = ["cattle", "kettle", "catalog"]
    private func apply(_ names: [String], _ text: String) -> String {
        SoundAlikeNames.apply(names, to: text, isOrdinaryWord: { ordinary.contains($0.lowercased()) })
    }

    @Test func aSpellingOfTheirNameBecomesTheirs() {
        #expect(apply(["Katelyn"], "I saw Caitlin today.") == "I saw Katelyn today.")
        #expect(apply(["Katelyn"], "Kaitlyn's birthday") == "Katelyn's birthday")
        #expect(apply(["Stephen"], "Steven called") == "Stephen called")
    }

    @Test func onlyANameThatSoundsTheSameChanges() {
        #expect(apply(["Katelyn"], "Catalina and Kate") == "Catalina and Kate")
        // Another person with the same consonants is still another person.
        #expect(apply(["Michael"], "I saw Michelle today.") == "I saw Michelle today.")
        #expect(apply(["Danielle"], "Daniel called") == "Daniel called")
        #expect(apply(["Katelyn"], "Cattle grazed") == "Cattle grazed")
        #expect(apply(["Katelyn"], "i saw caitlin") == "i saw caitlin")
        #expect(apply(["Katelyn"], "#Caitlin") == "#Caitlin")
        // Both are theirs: neither is guessed, and each keeps its own.
        #expect(apply(["Katelyn", "Caitlin"], "Caitlin and Kaitlyn") == "Caitlin and Kaitlyn")
    }

    @Test func soundKeys() {
        #expect(SoundAlikeNames.soundKey("Caitlin") == "kAtlIn")
        #expect(SoundAlikeNames.soundKey("Katelyn") == "kAtlIn")
        #expect(SoundAlikeNames.soundKey("Kaitlyn") == "kAtlIn")
        #expect(SoundAlikeNames.soundKey("Catalina") == "kAtAlInA")
        #expect(SoundAlikeNames.soundKey("Steven") == SoundAlikeNames.soundKey("Stephen"))
        #expect(SoundAlikeNames.soundKey("Brian") == SoundAlikeNames.soundKey("Bryan"))
        #expect(SoundAlikeNames.soundKey("Michael") != SoundAlikeNames.soundKey("Michelle"))
        #expect(SoundAlikeNames.soundKey("Daniel") != SoundAlikeNames.soundKey("Danielle"))
        #expect(SoundAlikeNames.soundKey("Erin") != SoundAlikeNames.soundKey("Aaron"))
        #expect(SoundAlikeNames.soundKey("Hannah") != SoundAlikeNames.soundKey("Anna"))
    }
}
