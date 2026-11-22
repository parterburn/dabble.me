import Foundation

/// A name the transcriber spelled another way takes the writer's spelling: "Caitlin" becomes
/// "Katelyn" for a writer who tags #Katelyn. `VocabularySpelling` only matches the same letters,
/// and the transcriber's words to expect only nudge it, so a name with a common spelling of its
/// own ("Caitlin", "Steven") still comes out that way.
///
/// This matches by sound instead, carefully: one capitalized word, three or more sounds, that
/// the dictionary doesn't know in lowercase ("Cattle" is never a name), that isn't one of the
/// writer's own names already, and that sounds like exactly one of them.
nonisolated enum SoundAlikeNames {
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    /// `names`: the writer's one-word, name-like spellings. `isOrdinaryWord`: the dictionary
    /// knows the word in lowercase, so it's left as heard.
    static func apply(_ names: [String], to text: String, isOrdinaryWord: (String) -> Bool) -> String {
        var byKey: [String: String] = [:]
        var ambiguous: Set<String> = []
        var own: Set<String> = []
        for name in names where name.count >= 3 && name.allSatisfy(\.isLetter) {
            own.insert(name.lowercased())
            let key = soundKey(name)
            guard key.count >= 3 else { continue }
            if let existing = byKey[key] {
                if existing.lowercased() != name.lowercased() { ambiguous.insert(key) }
            } else {
                byKey[key] = name
            }
        }
        // Two of their names sound alike (#Caitlin and #Katelyn): neither is guessed.
        for key in ambiguous { byKey[key] = nil }
        guard !byKey.isEmpty, !text.isEmpty else { return text }

        func replacement(for heard: String, after previous: Character?) -> String? {
            // A hashtag keeps its own spelling; so does part of a longer word ("O'Brien").
            if let previous, "#'’-".contains(previous) { return nil }
            // A run with a digit in it ("Caitlin2") isn't a name.
            guard heard.count >= 3, heard.allSatisfy(\.isLetter), heard.first?.isUppercase == true,
                  !own.contains(heard.lowercased()),
                  let name = byKey[soundKey(heard)],
                  !isOrdinaryWord(heard) else { return nil }
            return name
        }

        var output = ""
        output.reserveCapacity(text.count)
        var word = ""
        var before: Character?
        var last: Character?
        for character in text {
            if character.isLetter || character.isNumber {
                if word.isEmpty { before = last }
                word.append(character)
            } else {
                if !word.isEmpty {
                    output += replacement(for: word, after: before) ?? word
                    word = ""
                }
                output.append(character)
            }
            last = character
        }
        if !word.isEmpty { output += replacement(for: word, after: before) ?? word }
        return output
    }

    /// How a name sounds, roughly, in English: its consonants in order, with like sounds merged
    /// (c/k/q, s/z, f/v/ph), doubles and silent letters dropped, and a mark for a vowel it starts
    /// or ends on. "Caitlin", "Kaitlyn" and "Katelyn" are all "ktln"; "Catalina" is "ktlna".
    static func soundKey(_ name: String) -> String {
        var letters = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().filter { $0.isLetter && $0.isASCII }
        guard !letters.isEmpty else { return "" }
        for (from, to) in [("ph", "f"), ("ck", "k"), ("sch", "sk"), ("gh", "")] {
            letters = letters.replacingOccurrences(of: from, with: to)
        }
        for prefix in ["kn", "wr"] where letters.hasPrefix(prefix) { letters.removeFirst() }
        let chars = Array(letters)
        guard !chars.isEmpty else { return "" }

        func isVowel(_ index: Int) -> Bool {
            guard chars.indices.contains(index) else { return false }
            // "y" is a consonant only before a vowel at the start ("Yasmin").
            if chars[index] == "y", index == 0, chars.count > 1, vowels.contains(chars[1]), chars[1] != "y" { return false }
            return vowels.contains(chars[index])
        }

        var key = isVowel(0) ? "a" : ""
        var lastSound: Character?
        for (index, char) in chars.enumerated() {
            if isVowel(index) {
                lastSound = nil
                continue
            }
            let sound: String
            switch char {
            case "c": sound = isVowel(index + 1) && "eiy".contains(chars[index + 1]) ? "s" : "k"
            case "q": sound = "k"
            case "x": sound = "ks"
            case "z": sound = "s"
            case "v": sound = "f"
            // "h" and "w" count only before a vowel: "Hannah", "Wendy", not "Sarah", "Shawn".
            case "h", "w": sound = isVowel(index + 1) && (index == 0 || char == "w") ? String(char) : ""
            default: sound = String(char)
            }
            for s in sound where s != lastSound {
                key.append(s)
                lastSound = s
            }
        }
        // A sounded last vowel ("Katie", "Catalina"), not a silent "e" ("Kate").
        if let end = chars.indices.last, isVowel(end) {
            let silentE = chars[end] == "e" && end > 1 && !isVowel(end - 1)
            if !silentE { key.append("a") }
        }
        return key
    }
}
