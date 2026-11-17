import Foundation

/// The writer's template (Settings → Entry Template): headings or questions an entry can start
/// from. Kept on this device, formatted as an entry is. It goes into an entry from the composer's
/// lightbulb row, by holding the lightbulb button, or by itself at the start of every new entry.
enum EntryTemplate {
    static let blocksKey = "template.blocks"
    /// Every new entry starts with it.
    static let autoKey = "template.auto"

    static var blocks: [DocumentBlock] {
        get {
            #if DEBUG
            // UI tests: `-DabbleDebugTemplate "words"` is the template for that launch.
            if let words = UserDefaults.standard.string(forKey: "DabbleDebugTemplate"), !words.isEmpty {
                return [.paragraph(DocumentRun(words, bold: true))]
            }
            #endif
            guard let data = UserDefaults.standard.data(forKey: blocksKey) else { return [] }
            return (try? JSONDecoder().decode([DocumentBlock].self, from: data)) ?? []
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: blocksKey)
            } else if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: blocksKey)
            }
        }
    }

    static var addsToNewEntries: Bool { UserDefaults.standard.bool(forKey: autoKey) }

    /// Signing out: the next account doesn't inherit it.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: blocksKey)
        UserDefaults.standard.removeObject(forKey: autoKey)
    }
}
