import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// PRO features that run on Apple Intelligence's on-device model: hashtag suggestions while
/// writing, a reflection on an entry, and reflection prompts on Today. Nothing is sent to a server for
/// these; the model runs on the iPhone or iPad. Needs iOS 26 and a device with Apple Intelligence on.
@MainActor
enum JournalIntelligence {
    static let enabledKey = "ai.onDevice.enabled"

    /// The on-device model is ready (supported device, Apple Intelligence turned on, model downloaded).
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    /// Reflections, Today's prompt and hashtag suggestions: every plan (it runs on the device, so
    /// it costs nothing, and it gets people writing), where Apple Intelligence is supported and
    /// not turned off in Settings.
    static func isEnabled(for me: Me?) -> Bool {
        me != nil && isSupported && (UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true)
    }

    static func canSuggestHashtags(for me: Me?) -> Bool { isEnabled(for: me) }

    enum Failure: LocalizedError {
        case unavailable, noAnswer, noMatchingHashtags, declined

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Intelligence isn't available on this device right now."
            case .noAnswer: "Apple Intelligence couldn't come up with anything for this one."
            // Apple's on-device safety filters, which an app can't turn off.
            case .declined: "Apple Intelligence's on-device safety filters wouldn't respond to this entry. They can be cautious with hard moments; your entry is fine."
            case .noMatchingHashtags: "None of your hashtags fit this entry yet."
            }
        }
    }

    /// Up to 3 hashtags for an entry, minus ones already in it. Once the writer has hashtags, only
    /// from those (the model picks from the list; anything else it says is dropped). With none yet,
    /// it suggests new ones.
    static func suggestHashtags(for text: String, from existing: [String]) async throws -> [String] {
        guard !existing.isEmpty else { return try await suggestNewHashtags(for: text) }
        let already = Set(hashtags(in: text).map { $0.lowercased() })
        let candidates = existing.filter { !already.contains($0.lowercased()) }
        guard !candidates.isEmpty else { throw Failure.noMatchingHashtags }
        let list = candidates.prefix(150).map { "#\($0)" }.joined(separator: " ")
        let reply = try await respond(
            instructions: """
            You tag a private journal entry using only the writer's existing hashtags. Reply with the 1 to 3 \
            hashtags from the list that directly describe what this entry is about (a person, pet, place, \
            activity or theme it mentions), separated by spaces. Fewer is better: leave out any hashtag that \
            only loosely relates. Never create a hashtag that isn't in the list. If none fit, reply with NONE.
            """,
            prompt: "Hashtags: \(list)\n\nJournal entry:\n\(clipped(text, limit: 2500))",
            temperature: 0.2
        )
        // Keep only tags from the list, in the writer's own spelling.
        let spelling = Dictionary(candidates.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let picked = hashtags(in: reply).compactMap { spelling[$0.lowercased()] }.filter { seen.insert($0.lowercased()).inserted }
        guard !picked.isEmpty else { throw Failure.noMatchingHashtags }
        return Array(picked.prefix(3))
    }

    private static func suggestNewHashtags(for text: String) async throws -> [String] {
        let reply = try await respond(
            instructions: """
            You suggest hashtags for a private journal entry. Reply with 1 to 3 hashtags that directly describe \
            what the entry is about (a person, pet, place, activity or theme), separated by spaces, and nothing \
            else. Each starts with # and is a single lowercase word or joinedword, like #climbing #family.
            """,
            prompt: "Journal entry:\n\(clipped(text, limit: 2500))",
            temperature: 0.2
        )
        let already = Set(hashtags(in: text).map { $0.lowercased() })
        var seen = Set<String>()
        // Usually "#a #b"; tolerate bare words too.
        let found = hashtags(in: reply)
        let words = found.isEmpty ? reply.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).map(String.init).filter { $0.first?.isLetter == true } : found
        let picked = words.map { $0.lowercased() }.filter { !already.contains($0) && seen.insert($0).inserted }
        guard !picked.isEmpty else { throw Failure.noAnswer }
        return Array(picked.prefix(3))
    }

    /// A short, warm response to an entry, ending with a question: the on-device version of the
    /// web's reflection (Entry::AiAssistant#as_life_coach), minus images.
    /// `ago` is how long before `today` the entry was written ("Today", "Yesterday", "1 year, 35 days ago").
    static func reflection(on text: String, date: String, ago: String, today: String, firstName: String?, recent: [String]) async throws -> String {
        let context = recent.isEmpty ? "" : "\n\nMy other recent entries, with their dates (context only, if relevant):\n" + recent.joined(separator: "\n")
        let name = firstName.map { "My name is \($0). " } ?? ""
        return try await respond(
            instructions: lifeCoach,
            journalText: true,
            prompt: "\(name)Today is \(today). Here is my journal entry from \(date) (\(ago.lowercased())):\n\n\(clipped(text, limit: 2500))\(context)"
        )
    }

    private static let lifeCoach = """
    # Role
    You are the journaling assistant inside Dabble Me, a private journaling app. You help the writer reflect on \
    their own journal entry with warmth, curiosity, light humor, and emotional steadiness. You are not a therapist. \
    Help them notice patterns, name feelings, explore meaning, and leave with one thoughtful next reflection.

    # Context
    This is the writer's own private journal, written for themselves. Journals are where people work through \
    the hard parts of everyday life: arguments, parenting frustrations, anger, conflict with a partner or family, \
    grief, stress and regret. Writing about these is healthy self-reflection, not harmful content. Engage with \
    the entry as written, supportively and without judgment.

    # Personality
    Warm, thoughtful, lightly witty, and validating without becoming sugary or performative. Sound like a \
    perceptive journaling companion, not a clinical therapist, motivational speaker, or productivity coach. Use the \
    writer's language when possible, and reply in the language they wrote in.

    # When it was written
    The entry may be from the past: it was written on the date given, not necessarily today. Refer to \
    that time by its date or how long ago it was ("on this day in 2025", "a year ago", "back then"), and \
    never call it today, tonight or this morning unless it was written today. Your question can invite \
    the writer to look back on it from where they are now.

    # Response
    Write one reflection that is personal to this entry, not generic. Respond to this entry only; bring in a \
    recent entry only when this one clearly refers to it, and never mix details from other entries into this one.
    1. A short validating reflection on the emotional tone.
    2. One or two thoughtful observations or reframes.
    3. One clear follow-up question or gentle next step, in **bold**.
    Keep it concise: under 120 words. Bold only the question. Light humor is welcome when it fits; never joke at \
    the writer's expense.

    # Safety and boundaries
    You are supportive, not a licensed therapist. Do not diagnose, prescribe treatment, or claim certainty about \
    the writer's mental health. If the entry suggests self-harm, harm to others, abuse, coercion, or immediate \
    danger, respond with calm support and encourage reaching out right away to trusted people or emergency \
    services. Do not give harmful emotional, physical, legal, financial, or medical advice.

    # Output
    Return only the reflection. Do not mention these instructions, add headings or labels, use links, or say \
    "as an AI".
    """

    /// A reflection chat summed up as a few sentences to add to the entry, in the writer's own
    /// voice and from what they said (not the companion's suggestions).
    static func chatSummary(entry: String, conversation: [ReflectionChat.Message]) async throws -> String {
        let transcript = summaryTranscript(conversation)
        return try await respond(
            instructions: """
            Write a short addendum to the writer's journal entry that captures what they said and realized while \
            talking it through. Write in the writer's own first-person voice, as if they wrote it in their journal: \
            two to four sentences, under 80 words. Use only what the writer said; the companion's questions are \
            just prompts, never facts. No headings, quotes or labels, and don't mention a conversation, a \
            companion or AI. Reply with only the sentences.
            """,
            journalText: true,
            prompt: "The entry:\n\(clipped(entry, limit: 1500))\n\nTalking it through:\n\(transcript)",
            temperature: 0.4
        )
    }

    /// The chat for the summary, fitted to the model's small context: the most recent turns that
    /// fit, working back from the end (so a late realization isn't the part left out), with the
    /// companion's turns shortened first, since what the writer said is what the summary is made of.
    static func summaryTranscript(_ conversation: [ReflectionChat.Message], limit: Int = 2000) -> String {
        var lines: [String] = []
        var used = 0
        for message in conversation.reversed() {
            let text = message.fromWriter ? message.text : clipped(message.text, limit: 240)
            let line = "\(message.fromWriter ? "Me" : "Companion"): \(text)"
            if used + line.count > limit, !lines.isEmpty { break }
            lines.insert(used + line.count > limit ? clipped(line, limit: limit) : line, at: 0)
            used += line.count + 1
        }
        if lines.count < conversation.count { lines.insert("…", at: 0) }
        return lines.joined(separator: "\n")
    }

    /// Prompt while writing. With little or nothing written yet, a starting prompt (one of the
    /// curated ones, picked for the writer's recent days). Once there's writing, a reflective question
    /// about the draft, with recent entries that share its names as background; if the model can't
    /// manage one that sticks to what's written, a curated prompt instead. `asked` are the prompts
    /// already offered for this draft (not repeated).
    static func followUpQuestion(for draft: String, recent: [String], curated: [String], today: JournalDay,
                                 asked: [String]) async throws -> String {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 40 else {
            return try await startingPrompt(curated: curated, recent: recent, today: today, avoiding: asked)
        }
        let already = asked.isEmpty ? "" : "\n\nQuestions already asked (ask something different):\n" + asked.map { "- \($0)" }.joined(separator: "\n")
        // Only recent entries about the same people, places or #tags as the draft: the model latches
        // onto anything it's given, and the question should be about what they're writing now.
        let related = recent.prefix(5).filter { sharesNames(with: text, $0) }
        let background = related.isEmpty ? "" : "\n\nRelated recent entries, with dates (background only; everything in them happened on those days):\n" + clipped(related.joined(separator: "\n"), limit: 1000)
        do {
            return try await plainQuestion(groundedIn: text + "\n" + related.joined(separator: "\n")) {
                try await respond(
                    instructions: """
                    The writer is in the middle of today's journal entry and wants a nudge to go deeper. Pick one \
                    thing they wrote and ask one short, open question that invites them to reflect on it, using \
                    their own words for it. Good shapes: "How did it feel when…?", "What do you want to remember \
                    about…?", "What does … mean to you?", "What did … teach you?", "What would you tell yourself \
                    about…?". \(groundingRules) \(plainQuestionRules) Don't ask "why did you…" about what they \
                    did; it can sound like judgment. It's about today: never call it yesterday or another day. A related recent entry is background only; mention it only if \
                    the new entry is clearly about the same thing. Never give advice, and don't repeat a question \
                    already asked. Reply with only the question.
                    """,
                    journalText: true,
                    prompt: "The entry they're writing now:\n\(clipped(draft, limit: 2000))\(background)\(already)",
                    temperature: 0.7
                )
            }
        } catch let error where !(error is CancellationError) && !curated.isEmpty {
            return try await startingPrompt(curated: curated, recent: recent, today: today, avoiding: asked)
        }
    }

    /// Today's prompt, and Prompt on an empty page: one of the curated writing prompts (dabble.me's
    /// Inspirations), picked by the model for the writer's recent entries and shown word for word, so
    /// it's always a thoughtful question and never states anything about them. Without curated prompts
    /// (an older server), the model writes one from a recent entry.
    static func startingPrompt(curated: [String], recent: [String], today: JournalDay, avoiding asked: [String] = []) async throws -> String {
        let candidates = curated.filter { !asked.contains($0) }
        guard !candidates.isEmpty else { return try await reflectionPrompt(from: recent, today: today, avoiding: asked) }
        return await pickPrompt(from: candidates, recent: recent)
    }

    /// The curated prompt that best fits the writer's recent entries (the model answers with a
    /// number; the list is shuffled so it doesn't favor the top). Falls back to a random one.
    static func pickPrompt(from candidates: [String], recent: [String]) async -> String {
        // A few at a time: from a long list it keeps choosing the same favorite.
        let options = Array(candidates.shuffled().prefix(6))
        guard let fallback = options.first else { return "" }
        guard options.count > 1, !recent.isEmpty else { return fallback }
        let list = options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let reply = try? await respond(
            instructions: """
            You help someone choose a journaling prompt. Read their recent entries, then choose the one question \
            from the numbered list that would be most worthwhile for them to reflect on now, given what's going on \
            in their life. Prefer a question that invites reflection (feelings, meaning, what they're learning) \
            over one that asks them to recount events. Reply with only the number.
            """,
            journalText: true,
            prompt: "Their recent entries:\n\(clipped(recent.prefix(5).joined(separator: "\n"), limit: 1500))\n\nQuestions:\n\(list)",
            temperature: 0.3
        )
        let number = reply.flatMap { $0.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) } }
        guard let number, options.indices.contains(number - 1) else { return fallback }
        return options[number - 1]
    }

    /// The rule against making things up: questions only use what the writer wrote.
    private static let groundingRules = """
    Only mention people, places and events the entry names, in its words. The question must not assume \
    anything that isn't written: not what someone said, how anyone felt, when or where it happened, or what \
    came of it. If you'd need to know something, ask about it instead.
    """

    /// Whether every name in a question (a capitalized word after the first, other than "I") appears
    /// in `source`: the on-device model sometimes invents a person or place.
    static func namesAreGrounded(_ question: String, in source: String) -> Bool {
        let known = Set(source.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let words = question.split(whereSeparator: { $0.isWhitespace })
        for word in words.dropFirst() where word.first?.isUppercase == true {
            guard let name = word.split(whereSeparator: { !$0.isLetter }).first.map({ $0.lowercased() }),
                  name != "i" else { continue }
            if !known.contains(name) { return false }
        }
        return true
    }

    /// Whether a recent entry mentions a name, place or #tag from the draft (a capitalized word or a
    /// hashtag, other than "I").
    static func sharesNames(with draft: String, _ entry: String) -> Bool {
        let names = Set(draft.split(whereSeparator: { !$0.isLetter && $0 != "#" }).map(String.init).filter {
            $0.count > 1 && ($0.first == "#" || $0.first?.isUppercase == true)
        }.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#")) })
        let words = Set(entry.split(whereSeparator: { !$0.isLetter }).map { $0.lowercased() })
        return !names.isDisjoint(with: words)
    }

    /// How a prompt should read: a friend's question, not a workshop's.
    private static let plainQuestionRules = """
    Keep it under 15 words, one simple sentence in everyday words, easy to answer in a line or two, and \
    open (not a yes-or-no question). Don't use \
    abstract words like connect, connection, shape, resonate, reflect, journey, or meaningful, and don't stack \
    two ideas into one question.
    """

    /// Phrasing the on-device model reaches for that reads stiff in a prompt ("How does X's connection
    /// to Y shape your thoughts?"); a reply with them is asked for once more.
    private static let stiffPhrases = ["connect", "shape your", "shaped your", "resonat", "reflect on", "journey", "meaningful",
                                       "…", "..."] // the last two: a question shape copied with its blank

    /// One clean question from the model: the first line, without quotes or a label, asked again once
    /// if it came out stiff or (with `source`) names someone or something that isn't in it. A question
    /// that still invents a name is never shown: it throws instead.
    private static func plainQuestion(groundedIn source: String? = nil, _ ask: () async throws -> String) async throws -> String {
        func clean(_ reply: String) -> String {
            let line = reply.split(whereSeparator: \.isNewline).first.map(String.init) ?? reply
            return line.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”' ")).replacingOccurrences(of: "Question: ", with: "")
        }
        func grounded(_ question: String) -> Bool { source.map { namesAreGrounded(question, in: $0) } ?? true }
        func stiff(_ question: String) -> Bool { stiffPhrases.contains(where: question.lowercased().contains) }
        let first = clean(try await ask())
        if grounded(first), !stiff(first) { return first }
        let second = clean(try await ask())
        if grounded(second), !stiff(second) { return second }
        if grounded(first) { return first }
        if grounded(second) { return second }
        throw Failure.noAnswer
    }

    /// One reflection question inspired by recent entries.
    /// `recent` are dated lines from `dated(_:today:)`: the model needs to know those things happened
    /// on earlier days, or it asks about "today's" game that was yesterday. (No concrete examples in
    /// the instructions: the on-device model copies them, calling a hike "yesterday's game".)
    static func reflectionPrompt(from recent: [String], today: JournalDay, avoiding asked: [String] = []) async throws -> String {
        // One recent entry, picked at random: given them all, the model keeps choosing the same vivid
        // moment, so prompts never vary.
        let context = recent.prefix(5).randomElement() ?? ""
        let already = asked.isEmpty ? "" : "\n\nQuestions already asked (ask something different):\n" + asked.map { "- \($0)" }.joined(separator: "\n")
        let todayText = today.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return try await plainQuestion { try await respond(
            instructions: """
            You write one gentle journaling prompt for today, the way a curious friend would ask. A recent entry \
            is given with its date; everything in it happened on that earlier day, not today. Pick one concrete \
            thing from it (a person, a moment, a plan) and ask one plain question about it, in the past tense. \
            Use the entry's own words for it (a hike stays a hike), and don't say when it happened: no today, \
            yesterday or other days. \(plainQuestionRules) Never mention anything the entries don't say, and never \
            describe a past event as happening today. Reply with only the question.
            """,
            prompt: "Today is \(todayText).\n" + (context.isEmpty ? "No recent entries yet." : "A recent entry:\n\(clipped(context))") + already,
            temperature: 0.9
        ) }
    }

    /// "- Yesterday (Saturday, Nov 7): The basketball win was fun!"
    static func dated(_ entries: [EntrySummary], today: JournalDay) -> [String] {
        entries.filter { !$0.excerpt.isEmpty }.map { entry in
            guard let day = entry.day else { return "- \(entry.excerpt)" }
            let date = day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            return "- \(day.relative(to: today)) (\(date)): \(entry.excerpt)"
        }
    }

    static func hashtags(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "#([0-9]*[A-Za-z_][A-Za-z0-9_]*)")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// The on-device model has a small context window; long entries are cut down to their start.
    static func clipped(_ text: String, limit: Int = 3000) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// `journalText`: the prompt is the writer's own entry, which can be about hard things (a fight,
    /// a frustrating night with the kids). Apple's default guardrails reject much of that outright, so
    /// those use the guardrails Apple provides for working with the user's own, possibly sensitive,
    /// text. The model's own safety behavior still applies.
    private static func respond(instructions: String, journalText: Bool = false, prompt: String,
                                temperature: Double? = nil) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let model = journalText ? SystemLanguageModel(guardrails: .permissiveContentTransformations) : .default
            let session = LanguageModelSession(model: model, instructions: instructions)
            let reply: String
            do {
                reply = try await session.respond(to: prompt, options: GenerationOptions(temperature: temperature))
                    .content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation, .refusal: throw Failure.declined
                default: throw error
                }
            }
            guard !reply.isEmpty else { throw Failure.noAnswer }
            return reply
        }
        #endif
        throw Failure.unavailable
    }
}

/// After a reflection, a short back-and-forth about the entry with Apple Intelligence, on the
/// device: the writer answers the reflection's question and it replies, one question at a time.
/// Nothing is saved: the chat lives in the reflection's sheet and is gone when it closes.
@MainActor
@Observable
final class ReflectionChat {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let fromWriter: Bool
        var text: String
    }

    private(set) var messages: [Message] = []
    private(set) var isReplying = false

    private let entry: String
    private let date: String
    private let reflection: String
    private let firstName: String?
    /// The model session (a LanguageModelSession on iOS 26), kept for the whole chat so it
    /// remembers what was said.
    private var session: AnyObject?

    init(entry: String, date: String, reflection: String, firstName: String?) {
        self.entry = entry
        self.date = date
        self.reflection = reflection
        self.firstName = firstName
    }

    /// Sends the writer's message and streams the reply into the conversation.
    func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isReplying else { return }
        messages.append(Message(fromWriter: true, text: text))
        messages.append(Message(fromWriter: false, text: ""))
        let reply = messages.count - 1
        isReplying = true
        defer { isReplying = false }
        do {
            try await stream(text, into: reply)
        } catch ReflectionChat.Problem.full {
            // The model's memory is small: start over with the entry and the last few turns.
            session = nil
            do {
                try await stream(text, into: reply)
            } catch {
                messages[reply].text = Self.fallback(for: error)
            }
        } catch {
            messages[reply].text = Self.fallback(for: error)
        }
        if messages[reply].text.isEmpty { messages[reply].text = Self.fallback(for: JournalIntelligence.Failure.noAnswer) }
    }

    private enum Problem: Error { case full }

    /// Kind words instead of an error: Apple's safety filters can decline hard moments, and the
    /// writer shouldn't feel they did something wrong.
    private static func fallback(for error: Error) -> String {
        if case JournalIntelligence.Failure.declined = error {
            return "That sounds like a lot to sit with. I can't go further with this one here, but it might help to keep writing about it in your journal."
        }
        return "I couldn't come up with a reply just now. Try again in a moment."
    }

    private func stream(_ text: String, into index: Int) async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let session = (self.session as? LanguageModelSession) ?? makeSession()
            self.session = session
            do {
                for try await snapshot in session.streamResponse(to: text, options: GenerationOptions(temperature: 0.7)) {
                    messages[index].text = snapshot.content
                }
                messages[index].text = messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .exceededContextWindowSize: throw Problem.full
                case .guardrailViolation, .refusal: throw JournalIntelligence.Failure.declined
                default: throw error
                }
            }
            return
        }
        #endif
        throw JournalIntelligence.Failure.unavailable
    }

    #if canImport(FoundationModels)
    /// The entry, the reflection, and (when starting over) the last few turns, so it can carry on.
    @available(iOS 26.0, *)
    private func makeSession() -> LanguageModelSession {
        let recent = messages.dropLast(2).suffix(4)
            .map { "\($0.fromWriter ? "Writer" : "You"): \($0.text)" }.joined(separator: "\n")
        let name = firstName.map { "The writer's name is \($0). " } ?? ""
        let instructions = Self.companion + """

            # The entry
            \(name)Written \(date):
            \(JournalIntelligence.clipped(entry, limit: 1800))

            # Your reflection on it (the conversation starts after this)
            \(reflection)
            """ + (recent.isEmpty ? "" : "\n\n# The conversation so far (latest turns)\n\(recent)")
        return LanguageModelSession(model: SystemLanguageModel(guardrails: .permissiveContentTransformations), instructions: instructions)
    }
    #endif

    private static let companion = """
    # Role
    You are the journaling companion inside Dabble Me, a private journaling app. You already wrote a short \
    reflection on the writer's entry, ending with a question. Now they're answering, and you keep the \
    conversation going so they can process the entry. You are a curious, warm friend, not a therapist or coach.

    # Context
    This is the writer's own private journal. Journals are where people work through the hard parts of everyday \
    life: arguments, parenting frustrations, anger, grief, stress and regret. Writing about these is healthy \
    self-reflection. Engage with it supportively and without judgment.

    # How to reply
    - Short: two to four sentences, under 70 words.
    - Respond to what they just said first, in their own words where you can.
    - Then, usually, ask one gentle question that helps them go a little deeper. Only one question.
    - No advice, plans or lists unless they ask for them. Don't summarize the whole entry back to them.
    - Light humor is welcome when it fits; never at their expense. Reply in the language they write in.
    - You only know this entry and this conversation. Never claim to remember anything else.

    # Safety and boundaries
    Do not diagnose or claim certainty about their mental health. If they mention self-harm, harm to others, \
    abuse or immediate danger, respond with calm support and encourage reaching out right away to trusted people \
    or emergency services.

    # Output
    Plain text only: no headings, links or labels, and never say "as an AI".
    """
}
