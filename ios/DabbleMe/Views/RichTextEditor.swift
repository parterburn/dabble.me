import SwiftUI
import UIKit

extension RichText.Style {
    /// Serif body text that follows the user's Dynamic Type size.
    static var journal: RichText.Style {
        let body = UIFont.preferredFont(forTextStyle: .body)
        let serif = body.fontDescriptor.withDesign(.serif) ?? body.fontDescriptor
        return RichText.Style(baseFont: UIFont(descriptor: serif, size: 0), textColor: .label)
    }
}

/// Owns the UITextView behind `RichTextEditor` so SwiftUI (Save, link alert) can read
/// the document and drive formatting.
@MainActor
@Observable
final class RichTextEditorModel {
    let initialBlocks: [DocumentBlock]
    private(set) var isEmpty: Bool
    private(set) var isDirty = false
    /// Bumped on every change, so the composer can autosave a draft.
    private(set) var revision = 0

    /// Set while the link sheet is up; `linkText` is what the user is typing.
    var isEditingLink = false
    var linkText = ""
    private var linkRange = NSRange(location: 0, length: 0)

    @ObservationIgnored fileprivate weak var textView: UITextView?

    init(blocks: [DocumentBlock] = []) {
        initialBlocks = blocks
        isEmpty = blocks.isEmpty
    }

    var blocks: [DocumentBlock] {
        guard let textView else { return initialBlocks }
        return RichText.blocks(from: textView.attributedText)
    }

    func focus() {
        textView?.becomeFirstResponder()
    }

    /// Replaces everything in the editor (e.g. "Start Over" on a restored draft).
    func replace(with blocks: [DocumentBlock]) {
        textView?.attributedText = RichText.attributedString(from: blocks, style: .journal)
        textView?.typingAttributes = RichText.Style.journal.baseAttributes
        isEmpty = blocks.isEmpty
    }

    fileprivate func textDidChange() {
        isDirty = true
        revision += 1
        isEmpty = textView?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    // MARK: - Formatting

    enum Trait { case bold, italic }

    func toggle(_ trait: Trait) {
        guard let textView else { return }
        let base = RichText.Style.journal.baseFont
        let range = textView.selectedRange
        let has: (UIFont) -> Bool = { trait == .bold ? $0.isBold : $0.isItalic }
        let set: (UIFont, Bool) -> UIFont = { font, on in
            trait == .bold ? font.with(bold: on, italic: font.isItalic) : font.with(bold: font.isBold, italic: on)
        }

        if range.length == 0 {
            var attributes = textView.typingAttributes
            let font = attributes[.font] as? UIFont ?? base
            attributes[.font] = set(font, !has(font))
            textView.typingAttributes = attributes
            return
        }

        let storage = textView.textStorage
        var fonts: [(NSRange, UIFont)] = []
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            fonts.append((subrange, value as? UIFont ?? base))
        }
        let turnOn = !fonts.allSatisfy { has($0.1) }
        storage.beginEditing()
        for (subrange, font) in fonts {
            storage.addAttribute(.font, value: set(font, turnOn), range: subrange)
        }
        storage.endEditing()
        textView.selectedRange = range
        textDidChange()
    }

    func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange
        let key = NSAttributedString.Key.underlineStyle

        if range.length == 0 {
            var attributes = textView.typingAttributes
            let on = (attributes[key] as? Int ?? 0) != 0
            attributes[key] = on ? nil : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = attributes
            return
        }

        let storage = textView.textStorage
        var allUnderlined = true
        storage.enumerateAttribute(key, in: range) { value, _, stop in
            if (value as? Int ?? 0) == 0 {
                allUnderlined = false
                stop.pointee = true
            }
        }
        if allUnderlined {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        textView.selectedRange = range
        textDidChange()
    }

    /// Turns the selected lines into a list, or back into plain lines if they already are one.
    func toggleList(_ kind: DocumentBlock.Kind) {
        guard let textView else { return }
        let storage = textView.textStorage
        let string = storage.string as NSString
        let selection = textView.selectedRange
        let paragraphRange = string.paragraphRange(for: selection)

        var lines: [NSRange] = []
        string.enumerateSubstrings(in: paragraphRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            lines.append(lineRange)
        }
        if lines.isEmpty { lines = [NSRange(location: paragraphRange.location, length: 0)] }

        let removing = lines.allSatisfy { RichText.listPrefix(in: string.substring(with: $0))?.kind == kind }
        let plain = RichText.Style.journal.baseAttributes
        var delta = 0
        storage.beginEditing()
        for (index, line) in lines.enumerated().reversed() {
            let existing = RichText.listPrefix(in: string.substring(with: line))?.length ?? 0
            let replacement = removing ? "" : (kind == .bullet ? RichText.bulletPrefix : "\(index + 1). ")
            storage.replaceCharacters(in: NSRange(location: line.location, length: existing),
                                      with: NSAttributedString(string: replacement, attributes: plain))
            delta += replacement.utf16.count - existing
        }
        storage.endEditing()

        let endsWithNewline = paragraphRange.length > 0 && string.character(at: NSMaxRange(paragraphRange) - 1) == 0x0A
        let cursor = NSMaxRange(paragraphRange) + delta - (endsWithNewline ? 1 : 0)
        textView.selectedRange = NSRange(location: max(0, min(cursor, storage.length)), length: 0)
        textDidChange()
    }

    // MARK: - Links

    func beginLink() {
        guard let textView else { return }
        linkRange = textView.selectedRange
        let existing = linkRange.location < textView.textStorage.length
            ? textView.textStorage.attribute(.link, at: linkRange.location, effectiveRange: nil)
            : nil
        linkText = (existing as? URL)?.absoluteString ?? existing as? String ?? ""
        isEditingLink = true
    }

    /// Adds `linkText` as a link on the selection, or inserts it as linked text when nothing is selected.
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
            textView.selectedRange = range
        }
        textDidChange()
    }

    func removeLink() {
        guard let textView, linkRange.length > 0, NSMaxRange(linkRange) <= textView.textStorage.length else { return }
        textView.textStorage.removeAttribute(.link, range: linkRange)
        textDidChange()
    }

    var canRemoveLink: Bool { linkRange.length > 0 && !linkText.isEmpty }

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

        if line.utf16.count == prefix.length || line.dropFirst(prefix.length).allSatisfy(\.isWhitespace) {
            // Return on an empty item ends the list.
            storage.replaceCharacters(in: NSRange(location: lineRange.location, length: prefix.length), with: "")
            textView.selectedRange = NSRange(location: lineRange.location, length: 0)
        } else {
            let next = prefix.kind == .bullet ? RichText.bulletPrefix : "\(prefix.number + 1). "
            let insert = NSAttributedString(string: "\n" + next, attributes: RichText.Style.journal.baseAttributes)
            storage.replaceCharacters(in: range, with: insert)
            textView.selectedRange = NSRange(location: range.location + insert.length, length: 0)
        }
        textDidChange()
        return false
    }

    fileprivate func attach(_ textView: UITextView) {
        self.textView = textView
    }
}

struct RichTextEditor: UIViewRepresentable {
    let model: RichTextEditorModel

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.allowsEditingTextAttributes = true // B / I / U in the edit menu too
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 24, right: 12)
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.linkTextAttributes = [.foregroundColor: UIColor.tintColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        textView.attributedText = RichText.attributedString(from: model.initialBlocks, style: .journal)
        textView.typingAttributes = RichText.Style.journal.baseAttributes
        textView.inputAccessoryView = context.coordinator.makeToolbar()
        textView.accessibilityLabel = "Entry"
        model.attach(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {}

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

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", range.length == 0 else { return true }
            return model.handleReturn(in: textView, at: range)
        }

        /// Bold/italic/underline also live in the system edit menu (select text, then Format), the
        /// way Messages does it; this bar adds lists and links. It's taller than a classic 44pt
        /// toolbar so the glass buttons clear the keyboard's top edge, and short enough to fit an
        /// iPhone without spilling into a "…" menu (swipe down on the text to hide the keyboard).
        func makeToolbar() -> UIToolbar {
            let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
            func item(_ symbol: String, _ label: String, _ action: @escaping @MainActor (RichTextEditorModel) -> Void) -> UIBarButtonItem {
                let button = UIBarButtonItem(image: UIImage(systemName: symbol), primaryAction: UIAction { [weak model] _ in
                    if let model { action(model) }
                })
                button.accessibilityLabel = label
                return button
            }
            toolbar.items = [
                item("bold", "Bold") { $0.toggle(.bold) },
                item("italic", "Italic") { $0.toggle(.italic) },
                item("underline", "Underline") { $0.toggleUnderline() },
                .flexibleSpace(),
                item("list.bullet", "Bulleted List") { $0.toggleList(.bullet) },
                item("list.number", "Numbered List") { $0.toggleList(.number) },
                item("link", "Link") { $0.beginLink() },
            ]
            return toolbar
        }
    }
}

extension View {
    /// The link prompt for a `RichTextEditor`.
    func richTextLinkAlert(_ model: RichTextEditorModel) -> some View {
        @Bindable var model = model
        return alert("Link", isPresented: $model.isEditingLink) {
            TextField("https://", text: $model.linkText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Save") { model.applyLink() }
            if model.canRemoveLink {
                Button("Remove Link", role: .destructive) { model.removeLink() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select text first to link it, or add a web address on its own.")
        }
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
