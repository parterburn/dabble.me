import Foundation
#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

// Mirrors Api::EntryDocument on the server: an entry is a list of blocks, each a
// paragraph, list item or rule, made of runs that may be bold / italic / underlined / linked.

struct DocumentRun: Codable, Hashable, Sendable {
    var text: String
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var link: String?

    init(_ text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false, link: String? = nil) {
        self.text = text
        self.bold = bold ? true : nil
        self.italic = italic ? true : nil
        self.underline = underline ? true : nil
        self.link = link
    }

    var isBold: Bool { bold == true }
    var isItalic: Bool { italic == true }
    var isUnderlined: Bool { underline == true }

    func hasSameFormat(as other: DocumentRun) -> Bool {
        isBold == other.isBold && isItalic == other.isItalic && isUnderlined == other.isUnderlined && link == other.link
    }
}

struct DocumentBlock: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case paragraph, bullet, number, rule

        var isList: Bool { self == .bullet || self == .number }
    }

    var type: Kind
    var runs: [DocumentRun]?
    /// A list item inside another's list: 1 for the first list in. Top-level items have none.
    var level: Int? = nil

    /// How many lists deep a list item is (0 at the top; always 0 for other blocks).
    var depth: Int { type.isList ? min(max(level ?? 0, 0), RichText.maxListDepth) : 0 }

    static func paragraph(_ runs: DocumentRun...) -> DocumentBlock { DocumentBlock(type: .paragraph, runs: runs) }
}

/// Lays a document out as editable text and reads it back:
/// - paragraphs are separated by a blank line; "\n" inside a paragraph is a line break
/// - list items are lines starting with "• " or "1. " (typing "- " or "2) " works too); an item
///   in a list inside another starts four spaces further in for each list it's inside
/// - a line containing only "⸻" (or "---") is a divider, as between merged email replies
enum RichText {
    static let bulletPrefix = "• "
    /// What a list item starts with for each list it's inside.
    static let listIndent = "    "
    /// As deep as the server keeps (`Api::EntryDocument::MAX_LIST_LEVEL`).
    static let maxListDepth = 5
    static let ruleMarker = "⸻"
    private static let ruleMarkers: Set<String> = [ruleMarker, "---", "___", "***"]
    private static let attachmentCharacter = "\u{FFFC}"
    /// A line break inside a paragraph (Return starts a new paragraph instead).
    static let lineSeparator = "\u{2028}"

    struct Style {
        var baseFont: PlatformFont
        var textColor: PlatformColor

        var baseAttributes: [NSAttributedString.Key: Any] {
            [.font: baseFont, .foregroundColor: textColor]
        }

        func attributes(for run: DocumentRun) -> [NSAttributedString.Key: Any] {
            var attributes = baseAttributes
            attributes[.font] = baseFont.with(bold: run.isBold, italic: run.isItalic)
            if run.isUnderlined { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link, let url = URL(string: link) { attributes[.link] = url }
            return attributes
        }
    }

    /// Text pieces in display order; `run == nil` means unformatted structural text (separators, list prefixes).
    struct Segment: Equatable {
        let text: String
        let run: DocumentRun?
    }

    static func segments(for blocks: [DocumentBlock]) -> [Segment] {
        var segments: [Segment] = []
        let numbers = listNumbers(for: blocks)
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                // One line per paragraph: the space between them is paragraph spacing (see
                // applyListIndents), so Return starts a new paragraph rather than a bare line.
                segments.append(Segment(text: "\n", run: nil))
            }
            let indent = String(repeating: listIndent, count: block.depth)
            switch block.type {
            case .rule:
                segments.append(Segment(text: ruleMarker, run: nil))
                continue
            case .bullet:
                segments.append(Segment(text: indent + bulletPrefix, run: nil))
            case .number:
                segments.append(Segment(text: "\(indent)\(numbers[index]). ", run: nil))
            case .paragraph:
                break
            }
            for run in block.runs ?? [] where !run.text.isEmpty {
                // A line break within a paragraph (from <br>) is a line separator: it breaks the
                // line without starting a new paragraph (no paragraph spacing).
                segments.append(Segment(text: run.text.replacingOccurrences(of: "\n", with: lineSeparator), run: run))
            }
        }
        return segments
    }

    /// Each numbered item's number (0 for other blocks). A list counts from 1, and picks up where
    /// it left off after a list inside one of its items.
    static func listNumbers(for blocks: [DocumentBlock]) -> [Int] {
        // The list open at each depth: its kind and the last number given.
        var open: [(kind: DocumentBlock.Kind, count: Int)] = []
        return blocks.map { block in
            guard block.type.isList else {
                open = []
                return 0
            }
            let depth = min(block.depth, open.count)
            open.removeLast(open.count - min(open.count, depth + 1))
            if open.count == depth + 1, open[depth].kind != block.type { open.removeLast() }
            if open.count == depth { open.append((block.type, 0)) }
            open[depth].count += 1
            return block.type == .number ? open[depth].count : 0
        }
    }

    static func attributedString(from blocks: [DocumentBlock], style: Style) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for segment in segments(for: blocks) {
            let attributes = segment.run.map(style.attributes(for:)) ?? style.baseAttributes
            result.append(NSAttributedString(string: segment.text, attributes: attributes))
        }
        applyListIndents(to: result, font: style.baseFont)
        return result
    }

    /// Hangs list items: wrapped lines of a "• " or "1. " item line up with its text, not the marker.
    /// Also spaces paragraphs apart (a little under a line), and list items a little less, so each
    /// Return reads as a new paragraph.
    static func applyListIndents(to text: NSMutableAttributedString, font: PlatformFont) {
        let string = text.string as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            let line = string.substring(with: range)
            let prefix = listPrefix(in: line)
            let indent = prefix.map {
                (string.substring(with: NSRange(location: range.location, length: $0.length)) as NSString).size(withAttributes: [.font: font]).width
            } ?? 0
            let spacing = (font.pointSize * (prefix == nil ? 0.6 : 0.25)).rounded()
            let current = text.attribute(.paragraphStyle, at: enclosing.location, effectiveRange: nil) as? NSParagraphStyle
            guard enclosing.length > 0,
                  abs((current?.headIndent ?? 0) - indent) > 0.5 || abs((current?.paragraphSpacing ?? 0) - spacing) > 0.5 else { return }
            let style = (current?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.headIndent = indent
            style.paragraphSpacing = spacing
            text.addAttribute(.paragraphStyle, value: style, range: enclosing)
        }
    }

    static func blocks(from text: NSAttributedString) -> [DocumentBlock] {
        let string = text.string as NSString
        var blocks: [DocumentBlock] = []
        var paragraph: [DocumentRun] = []

        func flushParagraph() {
            let runs = cleaned(paragraph)
            if !runs.isEmpty { blocks.append(DocumentBlock(type: .paragraph, runs: runs)) }
            paragraph = []
        }

        var location = 0
        while true {
            let newline = string.range(of: "\n", range: NSRange(location: location, length: string.length - location))
            let end = newline.location == NSNotFound ? string.length : newline.location
            let lineRange = NSRange(location: location, length: end - location)
            let line = string.substring(with: lineRange)
            let trimmed = line.replacingOccurrences(of: attachmentCharacter, with: "").trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph() // blank lines just separate (paragraph spacing makes the gap)
            } else if ruleMarkers.contains(trimmed) {
                flushParagraph()
                blocks.append(DocumentBlock(type: .rule, runs: nil))
            } else if let prefix = listPrefix(in: line) {
                flushParagraph()
                let itemRange = NSRange(location: lineRange.location + prefix.length, length: lineRange.length - prefix.length)
                let runs = cleaned(self.runs(in: text, range: itemRange))
                if !runs.isEmpty { blocks.append(DocumentBlock(type: prefix.kind, runs: runs, level: prefix.level > 0 ? prefix.level : nil)) }
            } else {
                // Each line is its own paragraph: Return starts a new one.
                flushParagraph()
                paragraph = runs(in: text, range: lineRange)
            }

            if newline.location == NSNotFound { break }
            location = end + 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Hashtags

    static let hashtagScheme = "dabbleme-hashtag"

    /// Turns #hashtags into links (handled in-app to search for the tag). Skips text that's
    /// already a link and things like "C#" or URL fragments that aren't at a word start.
    static func linkingHashtags(in text: AttributedString) -> AttributedString {
        var result = text
        let string = String(result.characters)
        let regex = try! NSRegularExpression(pattern: "(?<![\\w&/#])#([0-9]*[A-Za-z_][A-Za-z0-9_]*)")
        for match in regex.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
            guard let range = Range(match.range, in: result),
                  result[range].link == nil,
                  let tagRange = Range(match.range(at: 1), in: string),
                  let url = URL(string: "\(hashtagScheme):\(string[tagRange])") else { continue }
            result[range].link = url
        }
        return result
    }

    /// Web addresses written into an entry ("dabble.me", "https://…") as links. Text already linked
    /// (Markdown links, #hashtags) is left alone.
    static func linkingURLs(in text: AttributedString) -> AttributedString {
        var result = text
        let string = String(result.characters)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        for match in detector.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
            guard let url = match.url, url.scheme?.hasPrefix("http") == true,
                  let range = Range(match.range, in: result), result[range].link == nil else { continue }
            result[range].link = url
        }
        return result
    }

    static func hashtag(from url: URL) -> String? {
        guard url.scheme == hashtagScheme else { return nil }
        let tag = url.absoluteString.dropFirst(hashtagScheme.count + 1)
        return tag.isEmpty ? nil : String(tag)
    }

    // MARK: - What's shown again under the text

    /// The text without what it ends with that's shown again right under it: the #tags among
    /// `hashtags` (dated ones, in their pills) and, with `songLinks`, links to Spotify songs (in
    /// the list of songs). Other tags at the end stay, and so does anything before the end. Text
    /// that's nothing but those is left as it is.
    static func droppingTrailing(hashtags: [String], songLinks: Bool, from text: String) -> String {
        var result = text
        // In either order ("…link #tag", "…#tag link"): until neither is at the end.
        for _ in 0..<4 {
            var next = result
            if let cut = trailingHashtagCut(hashtags, in: next) { next = cut.kept.isEmpty ? cut.lead : cut.lead + cut.kept }
            if songLinks, let range = next.range(of: trailingSongLinks, options: .regularExpression) { next.removeSubrange(range) }
            if next == result { break }
            result = next
        }
        return result.isEmpty ? text : result
    }

    /// The same for an entry's blocks: what its last block ends with.
    static func droppingTrailing(hashtags: [String], songLinks: Bool, from blocks: [DocumentBlock]) -> [DocumentBlock] {
        var result = blocks
        for _ in 0..<4 {
            guard let index = result.lastIndex(where: { $0.type != .rule && $0.runs?.isEmpty == false }),
                  var runs = result[index].runs else { break }
            let before = runs
            if songLinks {
                // Runs linked to a song (whatever they say), and the spaces around them.
                while let last = runs.last, last.link.map(isSongLink) == true || last.text.allSatisfy(\.isWhitespace) { runs.removeLast() }
                // And a song's address written out, unlinked.
                let text = runs.map(\.text).joined()
                if let range = text.range(of: trailingSongLinks, options: .regularExpression) {
                    runs = truncating(runs, to: text[..<range.lowerBound].count)
                }
            }
            if let cut = trailingHashtagCut(hashtags, in: runs.map(\.text).joined()) {
                runs = truncating(runs, to: cut.lead.count)
                if !cut.kept.isEmpty { runs.append(DocumentRun(cut.kept)) }
            }
            if runs == before { break }
            if runs.isEmpty {
                result.remove(at: index)
            } else {
                // The text ends where its words do.
                while let last = runs[runs.count - 1].text.last, last.isWhitespace { runs[runs.count - 1].text.removeLast() }
                result[index].runs = runs.filter { !$0.text.isEmpty }
            }
        }
        return result.contains { $0.type != .rule && $0.runs?.isEmpty == false } ? result : blocks
    }

    /// One or more links to Spotify songs at the end of a text: the address alone, or a Markdown
    /// link to it.
    private static let trailingSongLinks = #"(?:\s*(?:\[[^\]]*\]\(https?://open\.spotify\.com/track/[^)\s]+\)|<?https?://open\.spotify\.com/track/[^\s>]+>?))+\s*$"#

    private static func isSongLink(_ link: String) -> Bool {
        link.range(of: #"^https?://open\.spotify\.com/track/"#, options: .regularExpression) != nil
    }

    /// The runs up to `count` characters of their text.
    private static func truncating(_ runs: [DocumentRun], to count: Int) -> [DocumentRun] {
        var left = count
        var kept: [DocumentRun] = []
        for var run in runs where left > 0 {
            run.text = String(run.text.prefix(left))
            left -= run.text.count
            kept.append(run)
        }
        return kept
    }

    /// Splits `text` at the run of #tags it ends with: what's before it, and the tags of that run
    /// that aren't in `tags`. Nil when there's nothing to drop.
    private static func trailingHashtagCut(_ tags: [String], in text: String) -> (lead: String, kept: String)? {
        let dropped = Set(tags.map { $0.lowercased() })
        guard !dropped.isEmpty,
              let run = text.range(of: #"(?:(?<![\w&/#])#[0-9]*[A-Za-z_][A-Za-z0-9_]*\s*)+$"#, options: .regularExpression) else { return nil }
        let found = text[run].split(whereSeparator: \.isWhitespace)
        let kept = found.filter { !dropped.contains($0.dropFirst().lowercased()) }
        guard kept.count < found.count else { return nil }
        let lead = String(text[..<run.lowerBound])
        // With nothing left after it, the text ends where its words do.
        return kept.isEmpty ? (String(lead.reversed().drop(while: \.isWhitespace).reversed()), "") : (lead, kept.joined(separator: " "))
    }

    struct ListPrefix: Equatable {
        let kind: DocumentBlock.Kind
        /// UTF-16 length, for NSRange math: the spaces it's set in by, then the marker.
        let length: Int
        let number: Int
        /// How many lists deep: four spaces (or a tab) in for each.
        var level = 0
        /// UTF-16 length of the spaces before the marker.
        var indentLength = 0
    }

    static func listPrefix(in line: String) -> ListPrefix? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let columns = leading.reduce(0) { $0 + ($1 == "\t" ? listIndent.count : 1) }
        // Three spaces count as a level too (a number's own width, as some people indent).
        let level = min((columns + 1) / listIndent.count, maxListDepth)
        let rest = line.dropFirst(leading.count)
        for marker in [bulletPrefix, "- ", "* ", "•\t"] where rest.hasPrefix(marker) {
            return ListPrefix(kind: .bullet, length: leading.utf16.count + marker.utf16.count, number: 0,
                              level: level, indentLength: leading.utf16.count)
        }
        // "12. " or "12) "
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard (1...3).contains(digits.count) else { return nil }
        let after = rest.dropFirst(digits.count)
        guard after.hasPrefix(". ") || after.hasPrefix(") ") else { return nil }
        return ListPrefix(kind: .number, length: leading.utf16.count + digits.count + 2, number: Int(digits) ?? 1,
                          level: level, indentLength: leading.utf16.count)
    }

    private static func runs(in text: NSAttributedString, range: NSRange) -> [DocumentRun] {
        guard range.length > 0 else { return [] }
        var runs: [DocumentRun] = []
        let string = text.string as NSString
        text.enumerateAttributes(in: range) { attributes, subrange, _ in
            let font = attributes[.font] as? PlatformFont
            let underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
            let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
            runs.append(DocumentRun(string.substring(with: subrange).replacingOccurrences(of: lineSeparator, with: "\n"),
                                    bold: font?.isBold ?? false,
                                    italic: font?.isItalic ?? false,
                                    underline: underline,
                                    link: link))
        }
        return runs
    }

    /// Drops pasted image placeholders, trims the ends and merges neighbors with the same format.
    private static func cleaned(_ runs: [DocumentRun]) -> [DocumentRun] {
        var merged: [DocumentRun] = []
        for var run in runs {
            run.text = run.text.replacingOccurrences(of: attachmentCharacter, with: "")
            guard !run.text.isEmpty else { continue }
            if let last = merged.last, last.hasSameFormat(as: run) {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }
        if !merged.isEmpty {
            merged[0].text = String(merged[0].text.drop { $0 == " " || $0 == "\t" })
            let lastIndex = merged.count - 1
            while let last = merged[lastIndex].text.last, last.isWhitespace {
                merged[lastIndex].text.removeLast()
            }
        }
        return merged.filter { !$0.text.isEmpty }
    }
}

extension PlatformFont {
    var isBold: Bool {
        #if canImport(UIKit)
        fontDescriptor.symbolicTraits.contains(.traitBold)
        #else
        fontDescriptor.symbolicTraits.contains(.bold)
        #endif
    }

    var isItalic: Bool {
        #if canImport(UIKit)
        fontDescriptor.symbolicTraits.contains(.traitItalic)
        #else
        fontDescriptor.symbolicTraits.contains(.italic)
        #endif
    }

    func with(bold: Bool, italic: Bool) -> PlatformFont {
        #if canImport(UIKit)
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) } else { traits.remove(.traitBold) }
        if italic { traits.insert(.traitItalic) } else { traits.remove(.traitItalic) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
        #else
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) } else { traits.remove(.bold) }
        if italic { traits.insert(.italic) } else { traits.remove(.italic) }
        return NSFont(descriptor: fontDescriptor.withSymbolicTraits(traits), size: pointSize) ?? self
        #endif
    }
}
