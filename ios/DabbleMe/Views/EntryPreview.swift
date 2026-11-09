import SwiftUI

extension View {
    /// Long-press to preview an entry (Peek), with Open to go to it.
    func entryPreview(_ summary: EntrySummary, open: @escaping () -> Void) -> some View {
        modifier(EntryPreviewMenu(summary: summary, open: open))
    }

    /// For a list row: long-press to preview the entry, with Reflect, Edit and Open; tapping the
    /// preview opens it. UIKit's context menu on the row's cell, since SwiftUI's can't act on a
    /// tap on the preview (it just closes).
    func entryRowMenu(_ summary: EntrySummary, actions: EntryActions, open: @escaping () -> Void) -> some View {
        modifier(EntryRowMenu(summary: summary, actions: actions, open: open))
    }
}

private struct EntryRowMenu: ViewModifier {
    let summary: EntrySummary
    let actions: EntryActions
    let open: () -> Void
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.background {
            CellContextMenu(
                preview: { EntryPreview(summary: summary) },
                menu: {
                    var items: [UIMenuElement] = []
                    if JournalIntelligence.isEnabled(for: model.me) {
                        items.append(UIAction(title: "Reflect on This Entry", image: UIImage(named: "slab-sparkles")) { _ in
                            Task { await actions.reflect(on: summary.id, model: model) }
                        })
                    }
                    if model.me?.canEdit == true {
                        items.append(UIAction(title: "Edit", image: UIImage(named: "slab-edit")) { _ in
                            Task { await actions.edit(summary.id, model: model) }
                        })
                    }
                    items.append(UIAction(title: "Open", image: UIImage(named: "slab-expand")) { _ in open() })
                    return UIMenu(children: items)
                },
                commit: open
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Puts a UIKit context menu on the list cell around it (the view itself takes no touches, so
/// the row's taps and swipes work as before).
private struct CellContextMenu<Preview: View>: UIViewRepresentable {
    let preview: () -> Preview
    let menu: () -> UIMenu
    let commit: () -> Void

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.coordinator = context.coordinator
        anchor.isUserInteractionEnabled = false
        return anchor
    }

    func updateUIView(_ view: Anchor, context: Context) {
        context.coordinator.parent = self
        view.attach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Anchor: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        /// Onto the nearest list cell, replacing whatever entry menu a reused cell had.
        func attach() {
            guard window != nil, let coordinator else { return }
            var host = superview
            while let view = host, !(view is UICollectionViewCell) { host = view.superview }
            guard let cell = host else { return }
            if cell.interactions.contains(where: { ($0 as? UIContextMenuInteraction)?.delegate === coordinator }) { return }
            for interaction in cell.interactions where (interaction as? UIContextMenuInteraction)?.delegate is Coordinator {
                cell.removeInteraction(interaction)
            }
            cell.addInteraction(UIContextMenuInteraction(delegate: coordinator))
        }
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var parent: CellContextMenu

        init(parent: CellContextMenu) {
            self.parent = parent
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            let parent = parent
            return UIContextMenuConfiguration(identifier: nil, previewProvider: {
                let controller = UIHostingController(rootView: parent.preview())
                controller.view.backgroundColor = .systemBackground
                controller.preferredContentSize = controller.sizeThatFits(in: CGSize(width: 340, height: CGFloat.greatestFiniteMagnitude))
                return controller
            }, actionProvider: { _ in parent.menu() })
        }

        /// Tapping the preview opens the entry.
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                                    animator: UIContextMenuInteractionCommitAnimating) {
            animator.preferredCommitStyle = .dismiss
            let commit = parent.commit
            animator.addCompletion { commit() }
        }
    }
}

private struct EntryPreviewMenu: ViewModifier {
    let summary: EntrySummary
    let open: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { open() } label: { Label("Open", icon: "slab-expand") }
        } preview: {
            EntryPreview(summary: summary)
        }
    }
}

/// The preview shown on long-press: the date, the entry's text and its photo. Everything comes
/// with the timeline row (`preview_text`), because iOS sizes a preview once, when it opens: text
/// loaded afterwards got squeezed into a few truncated lines. Long entries fade out at the bottom.
struct EntryPreview: View {
    let summary: EntrySummary
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif

    /// Light Markdown from the server; list lines ("- item") show as bullets.
    private var text: String {
        (summary.previewText ?? summary.excerpt)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                for marker in ["- ", "* "] where line.hasPrefix(marker) { return "• " + line.dropFirst(2) }
                return String(line)
            }
            .joined(separator: "\n")
    }

    /// Room for the text (more without a photo), keeping the preview and its menu on one screen.
    private var textLimit: CGFloat { summary.imageURL == nil ? 460 : 250 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.day?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()) ?? summary.date)
                .font(.headline)
            // The whole entry when it fits; otherwise as much as fits, fading out. Never "…".
            ViewThatFits(in: .vertical) {
                entryText
                entryText
                    .frame(maxHeight: textLimit, alignment: .top)
                    .clipped()
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .frame(maxHeight: textLimit, alignment: .top)
            if summary.imageURL != nil, !summary.imageProcessing {
                // A fixed frame (the image loads after the preview is sized); the whole photo fits in it.
                AsyncImage(url: summary.thumbnailURL(width: 900)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipShape(.rect(cornerRadius: 10))
            }
        }
        .padding()
        .frame(width: 340, alignment: .topLeading)
    }

    private var entryText: some View {
        Text(RichText.linkingHashtags(in: AttributedString.journal(text)))
            .font(.system(size: bodySize * textSize.scale, design: fontStyle.design))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
