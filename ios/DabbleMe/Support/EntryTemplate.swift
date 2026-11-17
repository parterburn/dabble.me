import Foundation

/// The writer's template (Settings → Entry Template): headings or questions an entry can start
/// from. Kept on this device, formatted as an entry is. It goes into an entry from the composer's
/// lightbulb row, by holding the lightbulb button, or by itself at the start of every new entry.
enum EntryTemplate {
    static let runsKey = "template.runs"
    /// Where builds before 87 kept it, without its blank lines.
    static let blocksKey = "template.blocks"
    /// Every new entry starts with it.
    static let autoKey = "template.auto"

    /// The template as it was typed (`RichText.typedRuns`): its blank lines and empty list items
    /// are where the writing goes, so they're kept.
    static var runs: [DocumentRun] {
        get {
            #if DEBUG
            // UI tests: `-DabbleDebugTemplate "words"` is the template for that launch.
            if let words = UserDefaults.standard.string(forKey: "DabbleDebugTemplate"), !words.isEmpty {
                return [DocumentRun(words, bold: true)]
            }
            #endif
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: runsKey), let runs = try? JSONDecoder().decode([DocumentRun].self, from: data) { return runs }
            // One kept by an earlier build, as an entry's blocks.
            if let data = defaults.data(forKey: blocksKey), let blocks = try? JSONDecoder().decode([DocumentBlock].self, from: data) {
                return RichText.typedRuns(from: RichText.attributedString(from: blocks, style: .journal))
            }
            return []
        }
        set {
            UserDefaults.standard.removeObject(forKey: blocksKey)
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: runsKey)
            } else if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: runsKey)
            }
        }
    }

    static var addsToNewEntries: Bool { UserDefaults.standard.bool(forKey: autoKey) }

    /// Signing out: the next account doesn't inherit it.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: runsKey)
        UserDefaults.standard.removeObject(forKey: blocksKey)
        UserDefaults.standard.removeObject(forKey: autoKey)
    }
}
