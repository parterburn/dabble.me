import SwiftUI
import UIKit

/// An open entry's formatted text in a read-only text view, so a selection can run across
/// paragraphs and list items. (SwiftUI selects within one `Text` at a time, and formatted
/// entries are a `Text` per paragraph.) #hashtags and links stay tappable.
struct SelectableDocumentText: UIViewRepresentable {
    let blocks: [DocumentBlock]
    let fontSize: CGFloat
    let design: UIFontDescriptor.SystemDesign
    let lineSpacing: CGFloat
    @Environment(\.openURL) private var openURL

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false
        view.linkTextAttributes = [.foregroundColor: UIColor(named: "AccentColor") ?? .tintColor]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.openURL = openURL
        let text = attributedText
        if !(view.attributedText?.isEqual(to: text) ?? false) { view.attributedText = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.window?.windowScene?.screen.bounds.width ?? 390
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: ceil(height))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var attributedText: NSAttributedString {
        let base = UIFont.systemFont(ofSize: fontSize)
        let font = base.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: fontSize) } ?? base
        let text = NSMutableAttributedString(attributedString: RichText.attributedString(
            from: blocks, style: RichText.Style(baseFont: font, textColor: .label)))
        let whole = NSRange(location: 0, length: text.length)
        // Line spacing on top of each paragraph's own style (list items keep their hanging indent).
        text.enumerateAttribute(.paragraphStyle, in: whole) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            text.addAttribute(.paragraphStyle, value: style, range: range)
        }
        // #hashtags search, like everywhere else.
        let string = text.string
        let regex = try! NSRegularExpression(pattern: "(?<![\\w&/#])#([0-9]*[A-Za-z_][A-Za-z0-9_]*)")
        for match in regex.matches(in: string, range: whole) where text.attribute(.link, at: match.range.location, effectiveRange: nil) == nil {
            let tag = (string as NSString).substring(with: match.range(at: 1))
            if let url = URL(string: "\(RichText.hashtagScheme):\(tag)") { text.addAttribute(.link, value: url, range: match.range) }
        }
        return text
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var openURL: OpenURLAction?

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, let openURL else { return defaultAction }
            return UIAction { _ in openURL(url) }
        }
    }
}
