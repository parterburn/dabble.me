import Foundation

/// How a spoken entry is written down (Settings → Dictation).
enum DictationStyle: String, CaseIterable, Identifiable {
    /// Tidied: ums, repeats, false starts and spoken corrections go (`CleanupTagger`).
    case polished
    /// Exactly as the transcriber wrote it.
    case verbatim

    var id: String { rawValue }

    var label: String {
        switch self {
        case .polished: "Polished"
        case .verbatim: "Verbatim"
        }
    }

    var explanation: String {
        switch self {
        case .polished: "Takes out ums, repeated words and the words you correct (\"at 3, actually 4\" becomes \"at 4\"). It only removes words, never changes or adds one."
        case .verbatim: "Everything you say, as iOS heard it, ums included."
        }
    }
}

/// Settings → Dictation, kept on this device: the microphone on or off, the style, and the
/// writer's own words for the transcriber to expect (beside their hashtags).
enum DictationSettings {
    static let enabledKey = "dictation.enabled"
    static let styleKey = "dictation.style"
    static let wordsKey = "dictation.words"

    /// On unless turned off.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var style: DictationStyle {
        UserDefaults.standard.string(forKey: styleKey).flatMap(DictationStyle.init(rawValue:)) ?? .polished
    }

    /// The custom words, one a line in storage, in the order added.
    static var words: [String] { words(from: UserDefaults.standard.string(forKey: wordsKey) ?? "") }

    static func words(from stored: String) -> [String] {
        stored.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `words` with `word` added (trimmed, once, case aside), at most `Dictation.maxHints`.
    static func adding(_ word: String, to stored: String) -> String {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = words(from: stored)
        guard !word.isEmpty, !list.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }),
              list.count < Dictation.maxHints else { return stored }
        list.append(word)
        return list.joined(separator: "\n")
    }

    static func removing(_ word: String, from stored: String) -> String {
        words(from: stored).filter { $0 != word }.joined(separator: "\n")
    }
}
