import SwiftUI
import UIKit

extension RichText.Style {
    /// Serif body text that follows the user's Dynamic Type size.
    static var journal: RichText.Style {
        let body = UIFont.preferredFont(forTextStyle: .body)
        let serif = body.fontDescriptor.withDesign(.serif) ?? body.fontDescriptor
        // A little larger than body text (19pt at the default size), for comfortable writing.
        return RichText.Style(baseFont: UIFont(descriptor: serif, size: (body.pointSize * 1.12).rounded()), textColor: .label)
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
    /// Non-blank characters written so far.
    private(set) var characterCount = 0

    /// Set while the link sheet is up; `linkText` is what the user is typing.
    var isEditingLink = false
    var linkText = ""
    private var linkRange = NSRange(location: 0, length: 0)

    @ObservationIgnored fileprivate weak var textView: UITextView?

    init(blocks: [DocumentBlock] = []) {
        initialBlocks = blocks
        isEmpty = blocks.isEmpty
        characterCount = RichText.segments(for: blocks).map(\.text).joined().count
    }

    var blocks: [DocumentBlock] {
        guard let textView else { return initialBlocks }
        return RichText.blocks(from: textView.attributedText)
    }

    func focus() {
        textView?.becomeFirstResponder()
    }

    /// The entry as plain text (for on-device suggestions).
    var plainText: String { textView?.text ?? "" }

    /// Adds "#tag" at the end of the entry.
    func appendHashtag(_ tag: String) {
        guard let textView else { return }
        let storage = textView.textStorage
        let needsSpace = storage.length > 0 && !(storage.string.last?.isWhitespace ?? true)
        storage.append(NSAttributedString(string: (needsSpace ? " " : "") + "#\(tag)", attributes: RichText.Style.journal.baseAttributes))
        textView.selectedRange = NSRange(location: storage.length, length: 0)
        textDidChange()
    }

    // MARK: - Dictation (PRO, on device)

    private(set) var isDictating = false
    var dictationError: String?
    @ObservationIgnored private lazy var dictation = Dictation()
    /// Where the current dictation's words are, so each new transcript replaces the last.
    @ObservationIgnored private var dictationRange = NSRange(location: 0, length: 0)
    @ObservationIgnored private var dictationPrefix = ""

    func toggleDictation() {
        if isDictating {
            dictation.stop()
        } else {
            Task { await startDictation() }
        }
    }

    func stopDictation() {
        dictation.stop()
    }

    private func startDictation() async {
        guard let textView else { return }
        let selection = textView.selectedRange
        let string = textView.text as NSString
        // Separate from the word before the cursor.
        let before = selection.location > 0 ? string.substring(with: NSRange(location: selection.location - 1, length: 1)) : "\n"
        dictationPrefix = before.rangeOfCharacter(from: .whitespacesAndNewlines) == nil ? " " : ""
        dictationRange = selection
        dictation.onTranscript = { [weak self] text in self?.insertTranscript(text) }
        dictation.onStateChange = { [weak self] listening in
            self?.isDictating = listening
            self?.onDictationStateChange(listening)
        }
        do {
            try await dictation.start()
        } catch {
            dictationError = error.localizedDescription
        }
    }

    @ObservationIgnored fileprivate var onDictationStateChange: (Bool) -> Void = { _ in }

    private func insertTranscript(_ transcript: String) {
        guard let textView, !transcript.isEmpty else { return }
        let storage = textView.textStorage
        guard dictationRange.location + dictationRange.length <= storage.length else { return }
        let text = dictationPrefix + transcript
        let attributes = textView.typingAttributes
        storage.replaceCharacters(in: dictationRange, with: NSAttributedString(string: text, attributes: attributes))
        dictationRange = NSRange(location: dictationRange.location, length: (text as NSString).length)
        textView.selectedRange = NSRange(location: dictationRange.location + dictationRange.length, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)
        textDidChange()
    }

    /// Replaces everything in the editor (e.g. "Start Over" on a restored draft).
    func replace(with blocks: [DocumentBlock]) {
        textView?.attributedText = RichText.attributedString(from: blocks, style: .journal)
        textView?.typingAttributes = RichText.Style.journal.baseAttributes
        isEmpty = blocks.isEmpty
    }

    fileprivate func textDidChange() {
        if let textView {
            let selection = textView.selectedRange
            let storage = textView.textStorage
            storage.beginEditing()
            RichText.applyListIndents(to: storage, font: RichText.Style.journal.baseFont)
            storage.endEditing()
            textView.selectedRange = selection
        }
        isDirty = true
        revision += 1
        let trimmed = textView?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isEmpty = trimmed.isEmpty
        characterCount = trimmed.count
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

    /// Typing "- " or "* " at the start of a line starts a bulleted list ("1. " is already a
    /// numbered one), so lists don't need buttons.
    fileprivate func handleSpace(in textView: UITextView, at range: NSRange) -> Bool {
        let storage = textView.textStorage
        let string = storage.string as NSString
        let lineStart = string.lineRange(for: NSRange(location: range.location, length: 0)).location
        let typed = string.substring(with: NSRange(location: lineStart, length: range.location - lineStart))
        guard typed == "-" || typed == "*" else { return true }
        storage.replaceCharacters(in: NSRange(location: lineStart, length: range.location - lineStart),
                                  with: NSAttributedString(string: RichText.bulletPrefix, attributes: RichText.Style.journal.baseAttributes))
        textView.selectedRange = NSRange(location: lineStart + (RichText.bulletPrefix as NSString).length, length: 0)
        textView.typingAttributes = RichText.Style.journal.baseAttributes
        textDidChange()
        return false
    }

    fileprivate func attach(_ textView: UITextView) {
        self.textView = textView
    }
}

/// An item in the editor bar's "+" menu (photos, hashtag suggestions…), supplied by the composer.
struct EditorInsertItem {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    var isEnabled = true
    let action: @MainActor () -> Void
}

struct RichTextEditor: UIViewRepresentable {
    let model: RichTextEditorModel
    /// Shows the dictation (microphone) button in the bar.
    var allowsDictation = false
    var insertItems: [EditorInsertItem] = []

    /// Changes when the bar's buttons need rebuilding.
    fileprivate var barKey: String {
        "\(allowsDictation)|" + insertItems.map { "\($0.title)\($0.isEnabled)\($0.subtitle ?? "")" }.joined(separator: "|")
    }

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
        textView.inputAccessoryView = context.coordinator.makeToolbar(for: self)
        textView.accessibilityLabel = "Entry"
        model.attach(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.insertItems = insertItems
        guard context.coordinator.barKey != barKey, let toolbar = textView.inputAccessoryView as? UIToolbar else { return }
        context.coordinator.configure(toolbar, for: self)
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

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard range.length == 0 else { return true }
            if text == "\n" { return model.handleReturn(in: textView, at: range) }
            if text == " " { return model.handleSpace(in: textView, at: range) }
            return true
        }

        /// Bold/italic/underline also live in the system edit menu (select text, then Format), the
        /// way Messages does it; this bar adds lists and links. It's taller than a classic 44pt
        /// toolbar so the glass buttons clear the keyboard's top edge, and short enough to fit an
        /// iPhone without spilling into a "…" menu (swipe down on the text to hide the keyboard).
        fileprivate var barKey = ""
        /// The latest menu actions (their closures change as the composer's state does).
        var insertItems: [EditorInsertItem] = []
        private weak var micItem: UIBarButtonItem?

        func makeToolbar(for editor: RichTextEditor) -> UIToolbar {
            let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
            configure(toolbar, for: editor)
            model.onDictationStateChange = { [weak self] listening in self?.updateMic(listening: listening) }
            return toolbar
        }

        /// "+" (photos, hashtag suggestions), link, and dictation. Bold, italic and underline are in
        /// the text's edit menu (Format), and typing "- " or "1. " starts a list.
        func configure(_ toolbar: UIToolbar, for editor: RichTextEditor) {
            barKey = editor.barKey
            insertItems = editor.insertItems
            func item(_ symbol: String, _ label: String, _ action: @escaping @MainActor (RichTextEditorModel) -> Void) -> UIBarButtonItem {
                let button = UIBarButtonItem(image: UIImage(systemName: symbol), primaryAction: UIAction { [weak model] _ in
                    if let model { action(model) }
                })
                button.accessibilityLabel = label
                return button
            }
            var items: [UIBarButtonItem] = []
            if !editor.insertItems.isEmpty {
                let menu = UIMenu(children: editor.insertItems.indices.map { index in
                    let entry = editor.insertItems[index]
                    let action = UIAction(title: entry.title, subtitle: entry.subtitle, image: UIImage(systemName: entry.systemImage)) { [weak self] _ in
                        guard let self, index < self.insertItems.count else { return }
                        self.insertItems[index].action()
                    }
                    if !entry.isEnabled { action.attributes = .disabled }
                    return action
                })
                let plus = UIBarButtonItem(image: UIImage(systemName: "plus"), menu: menu)
                plus.accessibilityLabel = "Add"
                items.append(plus)
            }
            items.append(.flexibleSpace())
            items.append(item("link", "Link") { $0.beginLink() })
            if editor.allowsDictation {
                let mic = item("mic", "Dictate") { $0.toggleDictation() }
                micItem = mic
                items.append(mic)
            }
            toolbar.items = items
            updateMic(listening: model.isDictating)
        }

        private func updateMic(listening: Bool) {
            micItem?.image = UIImage(systemName: listening ? "stop.circle.fill" : "mic")
            micItem?.tintColor = listening ? .systemRed : nil
            micItem?.accessibilityLabel = listening ? "Stop Dictating" : "Dictate"
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
        .alert("Can't dictate", isPresented: .present($model.dictationError)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.dictationError ?? "")
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
