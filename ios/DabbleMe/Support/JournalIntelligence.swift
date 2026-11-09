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

    /// PRO, supported, and not turned off in Settings.
    static func isEnabled(for me: Me?) -> Bool {
        me?.isPro == true && isSupported && (UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true)
    }

    enum Failure: LocalizedError {
        case unavailable, noAnswer, noMatchingHashtags

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Intelligence isn't available on this device right now."
            case .noAnswer: "Apple Intelligence couldn't come up with anything for this one."
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
            prompt: "\(name)Today is \(today). Here is my journal entry from \(date) (\(ago.lowercased())):\n\n\(clipped(text, limit: 2500))\(context)"
        )
    }

    private static let lifeCoach = """
    # Role
    You are the journaling assistant inside Dabble Me, a private journaling app. You help the writer reflect on \
    their own journal entry with warmth, curiosity, light humor, and emotional steadiness. You are not a therapist. \
    Help them notice patterns, name feelings, explore meaning, and leave with one thoughtful next reflection.

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

    /// One reflection question inspired by recent entries.
    /// `recent` are dated lines from `dated(_:today:)`: the model needs to know those things happened
    /// on earlier days, or it asks about "today's" game that was yesterday. (No concrete examples in
    /// the instructions: the on-device model copies them, calling a hike "yesterday's game".)
    static func reflectionPrompt(from recent: [String], today: JournalDay) async throws -> String {
        let context = recent.prefix(5).joined(separator: "\n")
        let todayText = today.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return try await respond(
            instructions: """
            You write one gentle journaling prompt for today: a single question under 20 words. Recent entries \
            are given with their dates; everything in them happened on those earlier days, not today. If the \
            question mentions something from them, use the entry's own words for it (a hike stays a hike), say \
            when it was (yesterday, last week), and ask how it connects to today. Never mention anything the \
            entries don't say, and never describe a past event as happening today. Reply with only the question.
            """,
            prompt: "Today is \(todayText).\n" + (context.isEmpty ? "No recent entries yet." : "Recent entries:\n\(clipped(context))")
        )
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
    private static func clipped(_ text: String, limit: Int = 3000) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    private static func respond(instructions: String, prompt: String, temperature: Double? = nil) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let session = LanguageModelSession(model: .default, instructions: instructions)
            let reply = try await session.respond(to: prompt, options: GenerationOptions(temperature: temperature))
                .content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else { throw Failure.noAnswer }
            return reply
        }
        #endif
        throw Failure.unavailable
    }
}
