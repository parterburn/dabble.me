import SwiftUI
import UIKit

extension RichText.Style {
    /// Body text in the Entry Font (serif by default) that follows the user's Dynamic Type size
    /// and Entry Text Size.
    static var journal: RichText.Style {
        let size = (UserDefaults.standard.object(forKey: ReadingTextSize.storageKey) as? Int).flatMap(ReadingTextSize.init) ?? .standard
        // The size an open entry is read at (`EntryBody`: body text times the Entry Text Size),
        // and the same font, made the same way (`SelectableDocumentText`): a font taken from
        // the body text style sets its lines further apart than one of that size made plainly.
        // So what's written looks the same once it's saved.
        let pointSize = UIFont.preferredFont(forTextStyle: .body).pointSize * size.scale
        let plain = UIFont.systemFont(ofSize: pointSize)
        let font = plain.fontDescriptor.withDesign(ReadingFontStyle.current.uiDesign).map { UIFont(descriptor: $0, size: pointSize) } ?? plain
        // Its lines as far apart, too (`EntryBody`'s 5 points at the default size).
        return RichText.Style(baseFont: font, textColor: .label, lineSpacing: 5 * size.scale)
    }
}

/// Owns the UITextView behind `RichTextEditor` so SwiftUI (Save, the link row) can read
/// the document and drive formatting.
@MainActor
@Observable
final class RichTextEditorModel {
    let initialBlocks: [DocumentBlock]
    /// Set when the editor starts from text as typed, not from an entry's blocks.
    let initialTyped: [DocumentRun]?
    fileprivate let startsAtFirstBlank: Bool
    private(set) var isEmpty: Bool
    private(set) var isDirty = false
    /// Bumped on every change, so the composer can autosave a draft.
    private(set) var revision = 0
    /// Non-blank characters written so far.
    private(set) var characterCount = 0
    /// Some of the text is selected.
    private(set) var hasSelection = false
    /// The selected words (or, with none, what's typed next) are bold, italic or underlined, any
    /// of them: the bar's Format icon is filled in then.
    private(set) var isFormatted = false

    /// Set while the link row is open; `linkText` is what the user is typing.
    var isEditingLink = false
    var linkText = ""
    /// The row is for a link that's already there (it can be changed or removed).
    private(set) var isExistingLink = false
    /// Opened by selecting a link's text rather than from the Link button: it closes again when
    /// the selection moves off the link, and doesn't take the keyboard from the text.
    private(set) var linkOpenedBySelection = false
    /// Bumped each time the Link button opens the row, so the address field takes the keyboard.
    private(set) var linkFocusRequest = 0
    private var linkRange = NSRange(location: 0, length: 0)

    @ObservationIgnored fileprivate weak var textView: UITextView?
    /// Links are PRO: without them, a pasted address stays plain text.
    @ObservationIgnored var allowsLinks = true

    init(blocks: [DocumentBlock] = []) {
        initialBlocks = blocks
        initialTyped = nil
        startsAtFirstBlank = false
        isEmpty = blocks.isEmpty
        characterCount = RichText.segments(for: blocks).map(\.text).joined().count
    }

    /// Starting from text as it was typed (a template: `RichText.typedRuns`), blank lines and
    /// empty list items included.
    /// `atFirstBlank`: the cursor starts where the text first leaves room to write (a template),
    /// not at its end (a draft being picked up again).
    init(typed runs: [DocumentRun], atFirstBlank: Bool = true) {
        initialBlocks = []
        initialTyped = runs
        startsAtFirstBlank = atFirstBlank
        let text = runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        isEmpty = text.isEmpty
        characterCount = text.count
    }

    /// The text as it's typed, to keep as a template.
    var typedRuns: [DocumentRun] {
        guard let textView else { return initialTyped ?? [] }
        return RichText.typedRuns(from: textView.attributedText)
    }

    var blocks: [DocumentBlock] {
        guard let textView else { return initialTyped.map { RichText.blocks(from: RichText.attributedString(typed: $0, style: .journal)) } ?? initialBlocks }
        return RichText.blocks(from: textView.attributedText)
    }

    func unfocus() {
        textView?.resignFirstResponder()
    }

    func focus() {
        textView?.becomeFirstResponder()
    }

    /// The entry as plain text (for on-device suggestions).
    var plainText: String { textView?.text ?? "" }

    /// Tags the entry: the first time the word is already written ("Leo", "biscuit"), a "#" goes
    /// in front of it, keeping the writer's capitalization, and the cursor stays where it was
    /// (the writer goes on typing where they were). Otherwise "#tag" is added at the end, with
    /// the cursor after it.
    func addHashtag(_ tag: String) {
        guard let textView else { return }
        let storage = textView.textStorage
        let pattern = "(?<![#\\w])" + NSRegularExpression.escapedPattern(for: tag) + "(?!\\w)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: storage.string, range: NSRange(location: 0, length: storage.length)) {
            let attributes = storage.attributes(at: match.range.location, effectiveRange: nil)
            var cursor = textView.selectedRange
            storage.insert(NSAttributedString(string: "#", attributes: attributes), at: match.range.location)
            // Where it was, in the text as it now is: a "#" that went in before it moves it
            // along by one, and one inside a selection makes that one longer.
            if match.range.location < cursor.location {
                cursor.location += 1
            } else if match.range.location < cursor.location + cursor.length {
                cursor.length += 1
            }
            textView.selectedRange = cursor
            textDidChange()
            return
        }
        let needsSpace = storage.length > 0 && !(storage.string.last?.isWhitespace ?? true)
        storage.append(NSAttributedString(string: (needsSpace ? " " : "") + "#\(tag)", attributes: RichText.Style.journal.baseAttributes))
        textView.selectedRange = NSRange(location: storage.length, length: 0)
        textDidChange()
    }

    /// Tags the entry's own words: a "#" before the first use of each of `tags` that's a word
    /// in it and isn't a hashtag there already. The cursor stays where it was. Returns the
    /// ones it tagged.
    @discardableResult
    func tagWords(matching tags: [String]) -> [String] {
        guard let textView else { return [] }
        let storage = textView.textStorage
        var cursor = textView.selectedRange
        var tagged: [String] = []
        for tag in tags {
            let pattern = "(?<![#\\w])" + NSRegularExpression.escapedPattern(for: tag) + "(?!\\w)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: storage.string, range: NSRange(location: 0, length: storage.length)) else { continue }
            let attributes = storage.attributes(at: match.range.location, effectiveRange: nil)
            storage.insert(NSAttributedString(string: "#", attributes: attributes), at: match.range.location)
            if match.range.location < cursor.location { cursor.location += 1 }
            tagged.append(tag)
        }
        guard !tagged.isEmpty else { return [] }
        textView.selectedRange = cursor
        textDidChange()
        return tagged
    }

    /// Adds a prompt or a calendar event as its own bold paragraph where the writer is, with the
    /// cursor on a fresh line under it, ready for the answer: on the cursor's line when that
    /// line is empty (wherever in the entry it is), otherwise right under the line it's on.
    /// Nothing else in the entry moves, and the writer isn't sent to its end.
    func addQuestion(_ question: String) {
        let style = RichText.Style.journal
        var bold = style.baseAttributes
        bold[.font] = style.baseFont.with(bold: true, italic: false)
        let added = NSMutableAttributedString(string: question, attributes: bold)
        added.append(NSAttributedString(string: "\n", attributes: style.baseAttributes))
        addLines(added)
    }

    /// Adds the writer's template (Settings → Entry Template) as a prompt goes in: at the
    /// cursor, on lines of its own, with the cursor after it.
    func addTemplate(_ typed: [DocumentRun]) {
        guard !typed.isEmpty, let textView else { return }
        let lines = RichText.attributedString(typed: typed, style: .journal)
        let before = textView.textStorage.length
        addLines(lines)
        // The cursor goes where the template first leaves room to write, not after all of it.
        if let blank = RichText.firstBlank(in: lines.string) {
            let start = textView.selectedRange.location - lines.length
            if start >= 0, textView.textStorage.length > before {
                textView.selectedRange = NSRange(location: start + blank, length: 0)
                textView.scrollRangeToVisible(textView.selectedRange)
            }
        }
    }

    /// Puts `lines` under the cursor's line (or on it, when it's empty), the cursor after them.
    private func addLines(_ lines: NSAttributedString) {
        guard let textView else { return }
        let storage = textView.textStorage
        let string = storage.string as NSString
        let style = RichText.Style.journal

        // The cursor's line, without the line break that ends it.
        let cursor = min(NSMaxRange(textView.selectedRange), string.length)
        let line = string.paragraphRange(for: NSRange(location: cursor, length: 0))
        var length = line.length
        while length > 0, let last = UnicodeScalar(string.character(at: line.location + length - 1)), CharacterSet.newlines.contains(last) {
            length -= 1
        }
        let content = NSRange(location: line.location, length: length)
        let isEmptyLine = string.substring(with: content).trimmingCharacters(in: .whitespaces).isEmpty

        let added = NSMutableAttributedString()
        // Under a line with writing on it, on a line of its own.
        if !isEmptyLine { added.append(NSAttributedString(string: "\n", attributes: style.baseAttributes)) }
        added.append(lines)
        // An empty line is taken over (any stray spaces on it go); otherwise it goes in at the
        // line's end, before the break that ends it.
        let target = isEmptyLine ? content : NSRange(location: NSMaxRange(content), length: 0)
        storage.replaceCharacters(in: target, with: added)

        textView.typingAttributes = style.baseAttributes
        textView.selectedRange = NSRange(location: target.location + added.length, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)
        textDidChange()
        focus()
    }

    /// `replace(with:)`, with text as typed (a template to start over from).
    func replace(withTyped runs: [DocumentRun]) {
        textView?.attributedText = RichText.attributedString(typed: runs, style: .journal)
        textView?.typingAttributes = RichText.Style.journal.baseAttributes
        if let textView, let blank = RichText.firstBlank(in: textView.text) { textView.selectedRange = NSRange(location: blank, length: 0) }
        let text = (textView?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        isEmpty = text.isEmpty
        characterCount = text.count
    }

    /// Replaces everything in the editor (e.g. "Start Over" on a restored draft).
    func replace(with blocks: [DocumentBlock]) {
        textView?.attributedText = RichText.attributedString(from: blocks, style: .journal)
        textView?.typingAttributes = RichText.Style.journal.baseAttributes
        isEmpty = blocks.isEmpty
        // Keep the count in step too (Prompt shows once there's a couple of sentences).
        characterCount = (textView?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    fileprivate func textDidChange() {
        if let textView {
            let selection = textView.selectedRange
            let storage = textView.textStorage
            storage.beginEditing()
            let style = RichText.Style.journal
            RichText.applyListIndents(to: storage, font: style.baseFont, lineSpacing: style.lineSpacing)
            storage.endEditing()
            textView.selectedRange = selection
        }
        isDirty = true
        revision += 1
        let trimmed = textView?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isEmpty = trimmed.isEmpty
        characterCount = trimmed.count
    }

    // MARK: - Formatting

    /// The text view's own formatting, from the bar's Format menu: on the selection, or, with
    /// nothing selected, on what's typed next.
    func toggleBold() { format { $0.toggleBoldface(nil) } }
    func toggleItalic() { format { $0.toggleItalics(nil) } }
    func toggleUnderline() { format { $0.toggleUnderline(nil) } }

    private func format(_ change: (UITextView) -> Void) {
        guard let textView else { return }
        let hadSelection = textView.selectedRange.length > 0
        change(textView)
        // The entry changed only if words were restyled (the draft is saved, Save lights up).
        if hadSelection { textDidChange() }
        updateFormatState()
    }

    private func updateFormatState() {
        guard let textView else { return }
        func isStyled(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
            let font = attributes[.font] as? UIFont
            return font?.isBold == true || font?.isItalic == true || (attributes[.underlineStyle] as? Int ?? 0) != 0
        }
        let range = textView.selectedRange
        var styled = false
        if range.length > 0, NSMaxRange(range) <= textView.textStorage.length {
            textView.textStorage.enumerateAttributes(in: range) { attributes, _, stop in
                if isStyled(attributes) { styled = true; stop.pointee = true }
            }
        } else {
            styled = isStyled(textView.typingAttributes)
        }
        if styled != isFormatted { isFormatted = styled }
    }

    // MARK: - Links

    /// The link (its whole range and address) that `range` touches, if any.
    private func link(touching range: NSRange, in storage: NSTextStorage) -> (range: NSRange, address: String)? {
        guard storage.length > 0 else { return nil }
        var found: (NSRange, String)?
        // A caret counts when it's inside or at the end of a link.
        let probe = range.length > 0 ? range : NSRange(location: max(range.location - 1, 0), length: min(2, storage.length - max(range.location - 1, 0)))
        storage.enumerateAttribute(.link, in: NSIntersectionRange(probe, NSRange(location: 0, length: storage.length))) { value, at, stop in
            guard let value else { return }
            var whole = NSRange()
            _ = storage.attribute(.link, at: at.location, longestEffectiveRange: &whole, in: NSRange(location: 0, length: storage.length))
            found = (whole, (value as? URL)?.absoluteString ?? value as? String ?? "")
            stop.pointee = true
        }
        return found
    }

    /// Opens the link row from the Link button: for the link at the cursor or selection if there is
    /// one, otherwise a new link on the selection (or at the cursor).
    func beginLink() {
        guard let textView else { return }
        if let existing = link(touching: textView.selectedRange, in: textView.textStorage) {
            linkRange = existing.range
            linkText = existing.address
            isExistingLink = true
        } else {
            linkRange = textView.selectedRange
            linkText = ""
            isExistingLink = false
        }
        linkOpenedBySelection = false
        isEditingLink = true
        linkFocusRequest += 1
        markLinkedText()
    }

    /// The writer went back to the entry (a tap in it) with the link row open from the Link
    /// button, its address not yet put in: that's the link called off. The row closes and what
    /// was typed in it goes. (A row open on a link that's there already is the selection's, and
    /// follows it.)
    fileprivate func editingBegan() {
        guard isEditingLink, !linkOpenedBySelection else { return }
        endLink()
        linkText = ""
    }

    func endLink() {
        // The keyboard goes back to the entry while the address field is still there to hand it
        // over. Left holding it as its row is taken down (another row opened in its place), the
        // field kept the typing, and the next one opened only looked ready for it.
        if isEditingLink, let textView, !textView.isFirstResponder, textView.window != nil { textView.becomeFirstResponder() }
        unmarkLinkedText()
        isEditingLink = false
        linkOpenedBySelection = false
    }

    /// While the link row is open, the text it will link (or that's linked already) is tinted: once
    /// the address field has the keyboard, the entry's own selection highlight is gone, and nothing
    /// else would show what's being linked. A display-only tint: it's taken off when the row closes,
    /// and the document doesn't read background colors.
    private func markLinkedText() {
        guard let textView else { return }
        let storage = textView.textStorage
        unmarkLinkedText()
        let range = NSIntersectionRange(linkRange, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }
        let tint = (UIColor(named: "AccentColor") ?? .tintColor).withAlphaComponent(0.28)
        storage.addAttribute(.backgroundColor, value: tint, range: range)
    }

    private func unmarkLinkedText() {
        guard let textView else { return }
        let storage = textView.textStorage
        storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
        textView.typingAttributes[.backgroundColor] = nil
    }

    /// Selecting some or all of a link's text opens the row for it, to change or remove. It stays
    /// while the cursor is still in that link, and closes when it moves off.
    fileprivate func selectionDidChange() {
        // Words are selected in the text being written (the bar offers Format and Link then).
        let selecting = textView.map { $0.isFirstResponder && $0.selectedRange.length > 0 } ?? false
        if selecting != hasSelection { hasSelection = selecting }
        updateFormatState()
        guard let textView, textView.isFirstResponder else { return }
        let selection = textView.selectedRange
        let existing = link(touching: selection, in: textView.textStorage)
        if isEditingLink, isExistingLink, let existing, NSEqualRanges(existing.range, linkRange) { return }
        if selection.length > 0, let existing {
            showRow(for: existing)
        } else if isEditingLink, linkOpenedBySelection {
            endLink()
        }
    }

    /// Tapping a link in the editor opens its row too (rather than leaving for the browser).
    fileprivate func linkTapped(in range: NSRange) {
        guard let textView, let existing = link(touching: range, in: textView.textStorage) else { return }
        showRow(for: existing)
    }

    private func showRow(for existing: (range: NSRange, address: String)) {
        linkRange = existing.range
        linkText = existing.address
        isExistingLink = true
        linkOpenedBySelection = true
        isEditingLink = true
        markLinkedText()
    }

    /// Adds `linkText` as a link on the selection (or changes the existing link's address), or
    /// inserts it as linked text when nothing is selected.
    func applyLink() {
        guard let textView, let url = Self.normalizedURL(linkText) else { return }
        let storage = textView.textStorage
        let range = NSRange(location: min(linkRange.location, storage.length),
                            length: min(linkRange.length, storage.length - min(linkRange.location, storage.length)))
        if range.length == 0 {
            var attributes = textView.typingAttributes
            attributes[.link] = url
            storage.insert(NSAttributedString(string: url.absoluteString, attributes: attributes), at: range.location)
            textView.selectedRange = NSRange(location: range.location + url.absoluteString.utf16.count, length: 0)
        } else {
            storage.addAttribute(.link, value: url, range: range)
            textView.selectedRange = NSRange(location: NSMaxRange(range), length: 0)
        }
        endLink()
        textDidChange()
    }

    /// A web address pasted over selected text links the text, instead of taking its place.
    fileprivate func link(_ url: URL, onSelection range: NSRange) -> Bool {
        guard allowsLinks, let textView, range.length > 0, NSMaxRange(range) <= textView.textStorage.length,
              // Words, not just a line break or spaces.
              !textView.textStorage.attributedSubstring(from: range).string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        textView.textStorage.addAttribute(.link, value: url, range: range)
        textView.selectedRange = NSRange(location: NSMaxRange(range), length: 0)
        endLink()
        textDidChange()
        return true
    }

    /// A web address pasted by itself goes in as its own text, linked to itself, in place of
    /// whatever was selected (spaces or a line break: words would have been linked instead).
    /// What's typed after it isn't part of the link.
    fileprivate func insertLink(_ url: URL, replacing range: NSRange) -> Bool {
        guard allowsLinks, let textView, NSMaxRange(range) <= textView.textStorage.length else { return false }
        var attributes = textView.typingAttributes
        attributes[.backgroundColor] = nil
        attributes[.link] = url
        let address = url.absoluteString
        textView.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: address, attributes: attributes))
        textView.selectedRange = NSRange(location: range.location + (address as NSString).length, length: 0)
        textView.typingAttributes[.link] = nil
        textView.scrollRangeToVisible(textView.selectedRange)
        textDidChange()
        return true
    }

    func removeLink() {
        defer { endLink() }
        guard let textView, linkRange.length > 0, NSMaxRange(linkRange) <= textView.textStorage.length else { return }
        textView.textStorage.removeAttribute(.link, range: linkRange)
        textView.selectedRange = NSRange(location: NSMaxRange(linkRange), length: 0)
        textDidChange()
    }

    static func normalizedURL(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") && !trimmed.lowercased().hasPrefix("mailto:") {
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme),
              scheme == "mailto" || url.host() != nil else { return nil }
        return url
    }

    // MARK: - Return key continues lists

    fileprivate func handleReturn(in textView: UITextView, at range: NSRange) -> Bool {
        let storage = textView.textStorage
        let string = storage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: range.location, length: 0))
        let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard let prefix = RichText.listPrefix(in: line) else { return true }

        let indent = String(repeating: RichText.listIndent, count: prefix.level)
        if line.utf16.count == prefix.length || line.dropFirst(prefix.length).allSatisfy(\.isWhitespace) {
            // Return on an empty item ends the list; in a list inside another, it goes back out
            // to that one.
            let outer = prefix.level > 0 ? outerPrefix(before: lineRange.location, level: prefix.level - 1, in: string) : ""
            storage.replaceCharacters(in: NSRange(location: lineRange.location, length: prefix.length),
                                      with: NSAttributedString(string: outer, attributes: RichText.Style.journal.baseAttributes))
            textView.selectedRange = NSRange(location: lineRange.location + (outer as NSString).length, length: 0)
        } else {
            let next = indent + (prefix.kind == .bullet ? RichText.bulletPrefix : "\(prefix.number + 1). ")
            let insert = NSAttributedString(string: "\n" + next, attributes: RichText.Style.journal.baseAttributes)
            storage.replaceCharacters(in: range, with: insert)
            textView.selectedRange = NSRange(location: range.location + insert.length, length: 0)
        }
        textDidChange()
        return false
    }

    /// What the next item of the list at `level` starts with, going back out to it from a list
    /// inside it: its bullet or next number, found from the items above `location`.
    private func outerPrefix(before location: Int, level: Int, in string: NSString) -> String {
        let indent = String(repeating: RichText.listIndent, count: level)
        var end = location
        while end > 0 {
            let lineRange = string.lineRange(for: NSRange(location: end - 1, length: 0))
            let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard let prefix = RichText.listPrefix(in: line), prefix.level >= level else { break }
            if prefix.level == level {
                return indent + (prefix.kind == .bullet ? RichText.bulletPrefix : "\(prefix.number + 1). ")
            }
            end = lineRange.location
        }
        return indent + RichText.bulletPrefix
    }

    /// Typing "- " or "* " at the start of a line starts a bulleted list ("1. " is already a
    /// numbered one), so lists don't need buttons.
    fileprivate func handleSpace(in textView: UITextView, at range: NSRange) -> Bool {
        let storage = textView.textStorage
        let string = storage.string as NSString
        let lineStart = string.lineRange(for: NSRange(location: range.location, length: 0)).location
        let typed = string.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
        // Spaces before it set the item in, for a list inside another.
        let marker = typed.drop { $0 == " " || $0 == "\t" }
        guard marker == "-" || marker == "*" else { return true }
        let markerStart = range.location - (String(marker) as NSString).length
        storage.replaceCharacters(in: NSRange(location: markerStart, length: range.location - markerStart),
                                  with: NSAttributedString(string: RichText.bulletPrefix, attributes: RichText.Style.journal.baseAttributes))
        textView.selectedRange = NSRange(location: markerStart + (RichText.bulletPrefix as NSString).length, length: 0)
        textView.typingAttributes = RichText.Style.journal.baseAttributes
        textDidChange()
        return false
    }

    fileprivate func attach(_ textView: UITextView) {
        self.textView = textView
    }
}

/// The editor's text view. A pasted web address is a link: over selected words it links them,
/// and by itself it goes in as its own text, linked (anything else pastes as usual).
final class EditorTextView: UITextView {
    /// Links the selection; false when it didn't (links aren't allowed, nothing to link).
    var linksSelection: ((URL, NSRange) -> Bool)?
    /// Puts the address in as linked text; false when it didn't (links aren't allowed).
    var insertsLink: ((URL, NSRange) -> Bool)?

    override func paste(_ sender: Any?) {
        if let url = Self.address(in: UIPasteboard.general) {
            if selectedRange.length > 0, linksSelection?(url, selectedRange) == true { return }
            if insertsLink?(url, selectedRange) == true { return }
        }
        super.paste(sender)
    }

    /// The pasteboard's contents when they're one web address and nothing else.
    static func address(in pasteboard: UIPasteboard) -> URL? {
        address(from: pasteboard.string ?? pasteboard.url?.absoluteString)
    }

    static func address(from text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !text.contains(where: \.isWhitespace), let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host() != nil else { return nil }
        return url
    }
}

struct RichTextEditor: UIViewRepresentable {
    let model: RichTextEditorModel
    /// The bar over the keyboard: the composer's buttons at each end (photos on the left; tags
    /// and link on the right), and a key for what they show, so the bar is rebuilt when it changes.
    var leading: AnyView? = nil
    var trailing: AnyView? = nil
    var barKey = ""
    /// A row shown above the buttons (hashtags, a prompt, photos), part of the bar so it moves with
    /// the keyboard and is never covered by it.
    var row: AnyView? = nil

    func makeUIView(context: Context) -> UITextView {
        let textView = EditorTextView()
        textView.linksSelection = { [model] url, range in model.link(url, onSelection: range) }
        textView.insertsLink = { [model] url, range in model.insertLink(url, replacing: range) }
        textView.delegate = context.coordinator
        textView.allowsEditingTextAttributes = true // B / I / U in the edit menu too
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 24, right: 12)
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.linkTextAttributes = [.foregroundColor: UIColor.tintColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        if let typed = model.initialTyped {
            textView.attributedText = RichText.attributedString(typed: typed, style: .journal)
            // Ready to write where the template leaves room for it.
            if model.startsAtFirstBlank, let blank = RichText.firstBlank(in: textView.text) { textView.selectedRange = NSRange(location: blank, length: 0) }
        } else {
            textView.attributedText = RichText.attributedString(from: model.initialBlocks, style: .journal)
        }
        textView.typingAttributes = RichText.Style.journal.baseAttributes
        textView.inputAccessoryView = context.coordinator.makeBar(for: self)
        context.coordinator.keepTextClear(of: textView)
        textView.accessibilityLabel = "Entry"
        model.attach(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard let bar = textView.inputAccessoryView as? EditorBar else { return }
        bar.setRow(row)
        guard context.coordinator.barKey != barKey else { return }
        context.coordinator.configure(bar.toolbar, for: self)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let model: RichTextEditorModel

        init(model: RichTextEditorModel) {
            self.model = model
        }

        func textViewDidChange(_ textView: UITextView) {
            model.textDidChange()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            model.selectionDidChange()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            model.editingBegan()
            // (Words selected by the touch that brought the keyboard count from here.)
            model.selectionDidChange()
            padBottomForBar()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            model.selectionDidChange()
            // Once the keyboard (and the bar) has gone, or stayed for the link's address.
            DispatchQueue.main.async { [weak self] in self?.padBottomForBar() }
        }

        private weak var paddedTextView: UITextView?

        /// The bar sits over the bottom of the text. Whenever it's laid out (it appears, or a
        /// row opens in it), the text gets that much room at its end, so a long entry's last
        /// lines scroll clear of the bar and its row.
        func keepTextClear(of textView: UITextView) {
            paddedTextView = textView
            (textView.inputAccessoryView as? EditorBar)?.onLayout = { [weak self] in
                // After this pass: the text's own frame may still be settling around the keyboard.
                DispatchQueue.main.async { self?.padBottomForBar() }
            }
        }

        private func padBottomForBar() {
            guard let textView = paddedTextView else { return }
            var covered: CGFloat = 0
            if let bar = textView.inputAccessoryView, let barWindow = bar.window, let window = textView.window {
                let space = barWindow.screen.coordinateSpace
                // (The bar's own top: it can be taller than what it shows for a moment.)
                let shown = (bar as? EditorBar)?.shownHeight ?? bar.bounds.height
                let barTop = bar.convert(bar.bounds, to: space).maxY - shown
                // The text view's frame, not its (scrolled) bounds.
                let textBottom = (textView.superview ?? window).convert(textView.frame, to: space).maxY
                covered = max(0, textBottom - barTop)
            }
            guard abs(textView.contentInset.bottom - covered) > 0.5 else { return }
            let grew = covered > textView.contentInset.bottom
            textView.contentInset.bottom = covered
            textView.verticalScrollIndicatorInsets.bottom = covered
            // A row that opened over the cursor's line: bring that line back into view.
            if grew { textView.scrollRangeToVisible(textView.selectedRange) }
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link = textItem.content else { return defaultAction }
            let range = textItem.range
            return UIAction { [model] _ in model.linkTapped(in: range) }
        }

        /// A link held in the editor has no menu of iOS's (its web preview, Open Link, Share…).
        /// That preview took the keyboard and left the text view unable to take it back: the
        /// entry couldn't be written in again. Here a link is something to edit, which a tap
        /// does; holding it selects, as with any other word.
        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            if case .link = textItem.content { return nil }
            return .init(menu: defaultMenu)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard range.length == 0 else { return true }
            stopLinkAtItsEnd(in: textView, at: range.location)
            if text == "\n" { return model.handleReturn(in: textView, at: range) }
            if text == " " { return model.handleSpace(in: textView, at: range) }
            return true
        }

        /// Typing right after a link doesn't extend it (typing inside one still does).
        private func stopLinkAtItsEnd(in textView: UITextView, at location: Int) {
            let storage = textView.textStorage
            guard textView.typingAttributes[.link] != nil, location > 0, location <= storage.length,
                  storage.attribute(.link, at: location - 1, effectiveRange: nil) != nil,
                  location == storage.length || storage.attribute(.link, at: location, effectiveRange: nil) == nil else { return }
            textView.typingAttributes[.link] = nil
        }

        /// Bold/italic/underline also live in the system edit menu (select text, then Format), the
        /// way Messages does it; this bar adds lists and links. It's taller than a classic 44pt
        /// toolbar so the glass buttons clear the keyboard's top edge, and short enough to fit an
        /// iPhone without spilling into a "…" menu (swipe down on the text to hide the keyboard).
        fileprivate var barKey = ""
        private var hosts: [UIHostingController<AnyView>] = []

        func makeBar(for editor: RichTextEditor) -> EditorBar {
            let bar = EditorBar()
            configure(bar.toolbar, for: editor)
            bar.setRow(editor.row)
            return bar
        }

        /// The composer's buttons, always in view: photos on the left, tags and link on the right.
        /// Bold, italic and underline are in the text's edit menu (Format), typing "- " or "1. "
        /// starts a list, and the keyboard has dictation.
        func configure(_ toolbar: UIToolbar, for editor: RichTextEditor) {
            barKey = editor.barKey
            hosts = []
            func hosted(_ view: AnyView) -> UIBarButtonItem {
                let host = UIHostingController(rootView: view)
                host.view.backgroundColor = .clear
                host.view.frame.size = host.sizeThatFits(in: CGSize(width: 240, height: 44))
                hosts.append(host)
                return UIBarButtonItem(customView: host.view)
            }
            var items: [UIBarButtonItem] = []
            if let leading = editor.leading { items.append(hosted(leading)) }
            items.append(.flexibleSpace())
            if let trailing = editor.trailing { items.append(hosted(trailing)) }
            toolbar.items = items
        }
    }
}

/// The editor's bar over the keyboard: an optional row (sized to fit its width) above the
/// buttons. Its height follows the row, so the keyboard makes room for both.
final class EditorBar: UIView {
    static let toolbarHeight: CGFloat = 52
    let toolbar = UIToolbar()
    private let rowHost = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
    /// Behind the whole bar while a row is open, so the row reads on its own and not over the
    /// entry's text: Paper, a tray for the row and the buttons, apart from the page being written on.
    private let backdrop: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(named: "Paper")
        return view
    }()
    /// How far the tray runs on under the keyboard's top edge: its corners are round, and
    /// what's behind them should be the tray, not the page.
    private static let underKeyboard: CGFloat = 40
    private var rowHeight: CGFloat = 0
    private var hasRow = false
    /// Called when the bar is laid out or joins or leaves the screen (see `keepTextClear`).
    var onLayout: (() -> Void)?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.toolbarHeight))
        autoresizingMask = .flexibleHeight
        rowHost.safeAreaRegions = []
        // Clear over the backdrop.
        rowHost.view.backgroundColor = .clear
        rowHost.view.isHidden = true
        backdrop.isHidden = true
        addSubview(backdrop)
        addSubview(rowHost.view)
        addSubview(toolbar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: shownHeight)
    }

    /// The buttons and the row open over them.
    var shownHeight: CGFloat { rowHeight + Self.toolbarHeight }

    func setRow(_ row: AnyView?) {
        // A closed row is taken down, not just hidden, so reopening one starts it afresh (the link
        // row takes the keyboard when it appears).
        if hasRow, row == nil { rowHost.rootView = AnyView(EmptyView()) }
        hasRow = row != nil
        rowHost.view.isHidden = !hasRow
        backdrop.isHidden = !hasRow
        if let row { rowHost.rootView = row }
        updateRowHeight()
    }

    private func updateRowHeight() {
        let height = hasRow && bounds.width > 0
            ? rowHost.sizeThatFits(in: CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height.rounded(.up)
            : 0
        guard height != rowHeight else { return }
        rowHeight = height
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private var laidOutWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != laidOutWidth {
            laidOutWidth = bounds.width
            updateRowHeight() // a wrapping prompt takes more lines when narrower
        }
        // From the bar's foot up: the buttons, then the row right on top of them, and the backing
        // behind just those. The keyboard can leave the bar taller than that for a moment after
        // a row closes or gives way to a shorter one; whatever's above stays clear, so the entry
        // shows through it and not an empty band.
        let top = max(0, bounds.height - Self.toolbarHeight - rowHeight)
        backdrop.frame = CGRect(x: 0, y: top, width: bounds.width, height: bounds.height - top + Self.underKeyboard)
        rowHost.view.frame = CGRect(x: 0, y: top, width: bounds.width, height: rowHeight)
        toolbar.frame = CGRect(x: 0, y: bounds.height - Self.toolbarHeight, width: bounds.width, height: Self.toolbarHeight)
        onLayout?()
    }

    /// (And a touch up there is the entry's, not the bar's.)
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        point.y >= bounds.height - Self.toolbarHeight - rowHeight && super.point(inside: point, with: event)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onLayout?()
    }
}

extension RichText {
    /// Read-only rendering for SwiftUI `Text`, using the same layout as the editor.
    static func displayString(from blocks: [DocumentBlock]) -> AttributedString {
        var result = AttributedString()
        for segment in segments(for: blocks) {
            var piece = AttributedString(segment.text)
            if let run = segment.run {
                var intent: InlinePresentationIntent = []
                if run.isBold { intent.insert(.stronglyEmphasized) }
                if run.isItalic { intent.insert(.emphasized) }
                if !intent.isEmpty { piece.inlinePresentationIntent = intent }
                if run.isUnderlined { piece.underlineStyle = .single }
                if let link = run.link, let url = URL(string: link) { piece.link = url }
            }
            result += piece
        }
        return result
    }
}
