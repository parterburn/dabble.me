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
        case unavailable, noAnswer

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Intelligence isn't available on this device right now."
            case .noAnswer: "Apple Intelligence couldn't come up with anything for this one."
            }
        }
    }

    /// 3–5 hashtags for an entry, preferring tags the writer already uses, minus ones already in it.
    static func suggestHashtags(for text: String, preferring existing: [String]) async throws -> [String] {
        let usual = existing.prefix(25).map { "#\($0)" }.joined(separator: " ")
        let reply = try await respond(
            instructions: """
            You suggest hashtags for a private journal entry. Reply with 3 to 5 hashtags separated by spaces \
            and nothing else. Hashtags are single lowercase words or joinedwords with no spaces. Every hashtag \
            must describe something the entry is actually about (a place, activity, person, feeling or theme). \
            \(usual.isEmpty ? "" : "If one of the writer's usual hashtags clearly matches the entry, use that spelling: \(usual).")
            """,
            prompt: "Journal entry:\n\(clipped(text))"
        )
        let already = Set(hashtags(in: text).map { $0.lowercased() })
        var seen = Set<String>()
        return hashtags(in: reply).filter { tag in
            let key = tag.lowercased()
            return !already.contains(key) && seen.insert(key).inserted
        }.prefix(5).map { $0 }
    }

    /// A short, warm response to an entry, ending with a question: the on-device version of the
    /// web's DabbleMeGPT life-coach reply (Entry::AiAssistant#as_life_coach), minus web search,
    /// images and hashtags.
    static func reflection(on text: String, date: String, firstName: String?, recent: [String]) async throws -> String {
        let context = recent.isEmpty ? "" : "\n\nMy recent entries (context only, if relevant):\n" + recent.map { "- \($0)" }.joined(separator: "\n")
        let name = firstName.map { "My name is \($0). " } ?? ""
        return try await respond(
            instructions: lifeCoach,
            prompt: "\(name)Here is my journal entry for \(date):\n\n\(clipped(text, limit: 2500))\(context)"
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
    static func reflectionPrompt(from recent: [String]) async throws -> String {
        let context = recent.prefix(5).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return try await respond(
            instructions: """
            You write one gentle journaling prompt: a single question under 20 words that invites the writer \
            to reflect on today, building on themes from their recent entries. Reply with only the question.
            """,
            prompt: context.isEmpty ? "No recent entries yet." : "Recent entries:\n\(clipped(context))"
        )
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

    private static func respond(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let session = LanguageModelSession(model: .default, instructions: instructions)
            let reply = try await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else { throw Failure.noAnswer }
            return reply
        }
        #endif
        throw Failure.unavailable
    }
}
