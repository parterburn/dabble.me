import Foundation
import SwiftUI // (AttributedString's underline, in the preview)

/// The writer's template (Settings → Entry Template): headings or questions an entry can start
/// from. Kept on this device and on the account (`AccountSettings`), formatted as an entry is. A
/// new entry's empty page shows it, and a swipe right there puts it in; a held Write button on
/// Today starts an entry with it.
enum EntryTemplate {
    static let runsKey = "template.runs"
    /// Where builds before 87 kept it, without its blank lines.
    static let blocksKey = "template.blocks"
    /// Where builds before this one kept "Start New Entries with It", now gone: the empty page
    /// shows the template instead, a swipe away. Only ever cleared.
    static let legacyAutoKey = "template.auto"

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
            return storedRuns
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

    /// The template as kept on this phone (also on the account: `AccountSettings`).
    static var storedRuns: [DocumentRun] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: runsKey), let runs = try? JSONDecoder().decode([DocumentRun].self, from: data) { return runs }
        // One kept by an earlier build, as an entry's blocks.
        if let data = defaults.data(forKey: blocksKey), let blocks = try? JSONDecoder().decode([DocumentBlock].self, from: data) {
            return RichText.typedRuns(from: RichText.attributedString(from: blocks, style: .journal))
        }
        return []
    }

    /// The template as a new entry's empty page shows it: its words and formatting, without the
    /// blank lines and empty list items left for writing, so a few lines show as much of it as
    /// they can.
    static func preview(_ runs: [DocumentRun]) -> AttributedString {
        // Each line as its pieces of formatted text.
        var lines: [[DocumentRun]] = [[]]
        for run in runs {
            for (index, piece) in run.text.components(separatedBy: "\n").enumerated() {
                if index > 0 { lines.append([]) }
                if !piece.isEmpty {
                    var part = run
                    part.text = piece
                    lines[lines.count - 1].append(part)
                }
            }
        }
        // A line with no words of its own (blank, or a bare "•" or "1.") is room to write.
        let kept = lines.filter { !isRoomToWrite($0.map(\.text).joined()) }
        var preview = AttributedString()
        for (index, line) in kept.enumerated() {
            if index > 0 { preview.append(AttributedString("\n")) }
            for run in line {
                var part = AttributedString(run.text)
                var intent: InlinePresentationIntent = []
                if run.isBold { intent.insert(.stronglyEmphasized) }
                if run.isItalic { intent.insert(.emphasized) }
                if !intent.isEmpty { part.inlinePresentationIntent = intent }
                if run.isUnderlined { part.underlineStyle = .single }
                preview.append(part)
            }
        }
        return preview
    }

    /// A line with nothing of its own: blank, or only a list's marker ("•", "-", "*", "1.", "2)").
    /// A line of other figures or symbols ("1-10", "2025") is words.
    private static func isRoomToWrite(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || ["•", "-", "*"].contains(trimmed) { return true }
        guard let last = trimmed.last, last == "." || last == ")" else { return false }
        let number = trimmed.dropLast()
        return !number.isEmpty && number.allSatisfy(\.isASCII) && number.allSatisfy(\.isNumber)
    }

    /// Signing out: the next account doesn't inherit it (this one's comes back from the account).
    static func clear() {
        UserDefaults.standard.removeObject(forKey: runsKey)
        UserDefaults.standard.removeObject(forKey: blocksKey)
        UserDefaults.standard.removeObject(forKey: legacyAutoKey)
    }
}
