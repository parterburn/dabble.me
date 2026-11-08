import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// PRO features that run on Apple Intelligence's on-device model: hashtag suggestions while
/// writing, entry summaries, and reflection prompts on Today. Nothing is sent to a server for
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

    /// Two sentences about an entry, addressed to its writer.
    static func summary(of text: String) async throws -> String {
        let reply = try await respond(
            instructions: """
            You summarize a private journal entry for the person who wrote it. Write two short sentences \
            in the second person ("You ..."). Only use what is in the entry. No preamble.
            """,
            prompt: "Journal entry:\n\(clipped(text))"
        )
        return reply.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

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
