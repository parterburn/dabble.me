import SwiftUI
import UIKit

extension RichText.Style {
    /// Body text in the Entry Font (serif by default) that follows the user's Dynamic Type size
    /// and Entry Text Size.
    static var journal: RichText.Style {
        let body = UIFont.preferredFont(forTextStyle: .body)
        let serif = body.fontDescriptor.withDesign(ReadingFontStyle.current.uiDesign) ?? body.fontDescriptor
        let size = (UserDefaults.standard.object(forKey: ReadingTextSize.storageKey) as? Int).flatMap(ReadingTextSize.init) ?? .standard
        // A little larger than body text (19pt at the default size), for comfortable writing.
        return RichText.Style(baseFont: UIFont(descriptor: serif, size: (body.pointSize * 1.12 * size.scale).rounded()), textColor: .label)
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

    /// Tags the entry: the first time the word is already written ("Leo", "biscuit"), a "#" goes
    /// in front of it, keeping the writer's capitalization; otherwise "#tag" is added at the end.
    func addHashtag(_ tag: String) {
        guard let textView else { return }
        let storage = textView.textStorage
        let pattern = "(?<![#\\w])" + NSRegularExpression.escapedPattern(for: tag) + "(?!\\w)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: storage.string, range: NSRange(location: 0, length: storage.length)) {
            let attributes = storage.attributes(at: match.range.location, effectiveRange: nil)
            storage.insert(NSAttributedString(string: "#", attributes: attributes), at: match.range.location)
            textView.selectedRange = NSRange(location: match.range.location + match.range.length + 1, length: 0)
            textDidChange()
            return
        }
        let needsSpace = storage.length > 0 && !(storage.string.last?.isWhitespace ?? true)
        storage.append(NSAttributedString(string: (needsSpace ? " " : "") + "#\(tag)", attributes: RichText.Style.journal.baseAttributes))
        textView.selectedRange = NSRange(location: storage.length, length: 0)
        textDidChange()
    }

    /// Adds an "Ask Me" question as its own bold paragraph at the end, with the cursor on a fresh
    /// line under it, ready for the answer.
    func addQuestion(_ question: String) {
        guard let textView else { return }
        let storage = textView.textStorage
        let style = RichText.Style.journal
        var bold = style.baseAttributes
        bold[.font] = style.baseFont.with(bold: true, italic: false)
        let lead = storage.length == 0 || storage.string.hasSuffix("\n") ? "" : "\n"
        storage.beginEditing()
        storage.append(NSAttributedString(string: lead, attributes: style.baseAttributes))
        storage.append(NSAttributedString(string: question, attributes: bold))
        storage.append(NSAttributedString(string: "\n", attributes: style.baseAttributes))
        storage.endEditing()
        textView.typingAttributes = style.baseAttributes
        textView.selectedRange = NSRange(location: storage.length, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)
        textDidChange()
        focus()
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
        textView.inputAccessoryView = context.coordinator.makeBar(for: self)
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
    private var rowHeight: CGFloat = 0
    private var hasRow = false

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.toolbarHeight))
        autoresizingMask = .flexibleHeight
        rowHost.safeAreaRegions = []
        rowHost.view.backgroundColor = .systemBackground
        rowHost.view.isHidden = true
        addSubview(rowHost.view)
        addSubview(toolbar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: rowHeight + Self.toolbarHeight)
    }

    func setRow(_ row: AnyView?) {
        hasRow = row != nil
        rowHost.view.isHidden = !hasRow
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
        rowHost.view.frame = CGRect(x: 0, y: 0, width: bounds.width, height: rowHeight)
        toolbar.frame = CGRect(x: 0, y: bounds.height - Self.toolbarHeight, width: bounds.width, height: Self.toolbarHeight)
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
