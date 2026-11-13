import SwiftUI
import UIKit

extension View {
    /// Long-press to preview an entry (Peek), with Open to go to it.
    func entryPreview(_ summary: EntrySummary, open: @escaping () -> Void) -> some View {
        modifier(EntryPreviewMenu(summary: summary, open: open))
    }

    /// For a list row: long-press to preview the entry, with Reflection, Edit, Open and More (the
    /// Actions sheet); tapping the
    /// preview opens it. UIKit's context menu on the row's cell, since SwiftUI's can't act on a
    /// tap on the preview (it just closes).
    func entryRowMenu(_ summary: EntrySummary, actions: EntryActions, open: @escaping () -> Void) -> some View {
        modifier(EntryRowMenu(summary: summary, actions: actions, open: open))
    }
}

extension View {
    /// Long-press a day (a square of Stats' grid, a date in Jump to a Day): its entry in the
    /// Journal's preview, with Open; or, for a day without one, that nothing's written, with
    /// Write Entry (when `write` is given). `summary` is the day's entry when it's already to hand.
    func dayPreview(_ day: JournalDay, isWritten: Bool, summary: EntrySummary? = nil, model: AppModel,
                    open: @escaping () -> Void, write: (() -> Void)?) -> some View {
        background {
            AreaContextMenu(
                preview: { DayPreview(day: day, isWritten: isWritten, summary: summary, model: model) },
                menu: {
                    if isWritten {
                        return UIMenu(children: [UIAction(title: "Open", image: UIImage(named: "slab-expand")) { _ in open() }])
                    } else if let write {
                        return UIMenu(children: [UIAction(title: "Write Entry", image: UIImage(named: "slab-plus")) { _ in write() }])
                    }
                    return UIMenu(children: [])
                },
                // A tap on the day's entry opens it; on "Nothing written", it just closes.
                commit: isWritten ? open : nil
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The preview for a day: its entry (looked up when it wasn't passed in; the frame is set first,
/// since iOS sizes a preview when it opens), or the date over "Nothing written on this day."
private struct DayPreview: View {
    let day: JournalDay
    let isWritten: Bool
    let summary: EntrySummary?
    /// Passed in: a preview doesn't inherit the app's environment.
    let model: AppModel
    @State private var loaded: EntrySummary?
    @State private var failed = false

    var body: some View {
        if let summary = summary ?? loaded {
            EntryPreview(summary: summary)
                .frame(maxHeight: summary == self.summary ? nil : 420, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                    .font(.headline)
                if !isWritten || failed {
                    Text(isWritten ? "Couldn't load this day." : "Nothing written on this day.")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding()
            .frame(width: 340, alignment: .topLeading)
            .frame(height: isWritten ? 420 : nil, alignment: .top)
            .task {
                guard isWritten else { return }
                loaded = try? await model.entrySummary(on: day)
                failed = loaded == nil
            }
        }
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
                        items.append(UIAction(title: "Reflection", image: UIImage(named: "slab-sparkles")) { _ in
                            Task { await actions.reflect(on: summary.id, model: model) }
                        })
                    }
                    if model.me?.canEdit == true {
                        items.append(UIAction(title: "Edit", image: UIImage(named: "slab-edit")) { _ in
                            Task { await actions.edit(summary.id, model: model) }
                        })
                    }
                    items.append(UIAction(title: "Open", image: UIImage(named: "slab-expand")) { _ in open() })
                    // The rest (Delete, the entry's tags): the Actions sheet.
                    items.append(UIAction(title: "More", image: UIImage(named: "slab-more")) { _ in
                        Task { await actions.showActions(for: summary.id, model: model) }
                    })
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

        /// Tapping the preview opens the entry: the preview grows into it (iOS's "pop") while the
        /// entry is pushed underneath without its own slide, so there's no close-then-open jump.
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                                    animator: UIContextMenuInteractionCommitAnimating) {
            animator.preferredCommitStyle = .pop
            let commit = parent.commit
            animator.addAnimations {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { commit() }
            }
        }
    }
}

private struct EntryPreviewMenu: ViewModifier {
    let summary: EntrySummary
    let open: () -> Void

    func body(content: Content) -> some View {
        content.background {
            AreaContextMenu(
                preview: { EntryPreview(summary: summary) },
                menu: { UIMenu(children: [UIAction(title: "Open", image: UIImage(named: "slab-expand")) { _ in open() }]) },
                commit: open
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A UIKit context menu for a view that isn't a list row (a photo in the grid, a day's square):
/// like SwiftUI's, but a tap on the preview can act (`commit`), where SwiftUI's only closes. The
/// view itself takes no touches, so taps, scrolling and pinches around it work as before: the
/// menu belongs to the scroll view (or the screen) it sits in, which asks its marks whose spot was
/// held.
private struct AreaContextMenu<Preview: View>: UIViewRepresentable {
    let preview: () -> Preview
    let menu: () -> UIMenu
    let commit: (() -> Void)?

    func makeUIView(context: Context) -> AreaMenuMark {
        let mark = AreaMenuMark()
        mark.isUserInteractionEnabled = false
        mark.backgroundColor = .clear
        return mark
    }

    func updateUIView(_ mark: AreaMenuMark, context: Context) {
        let preview = preview
        mark.preview = {
            let controller = UIHostingController(rootView: preview())
            controller.view.backgroundColor = .systemBackground
            controller.preferredContentSize = controller.sizeThatFits(in: CGSize(width: 340, height: CGFloat.greatestFiniteMagnitude))
            return controller
        }
        mark.menu = menu
        mark.commit = commit
        mark.attach()
    }
}

/// Where a held view is, and what holding it shows.
final class AreaMenuMark: UIView {
    var preview: (() -> UIViewController)?
    var menu: (() -> UIMenu)?
    var commit: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attach()
    }

    /// Joins the menu of the nearest scroll view around it (else of the SwiftUI view it's drawn in).
    func attach() {
        guard window != nil else { return }
        var host = superview
        while let view = host, !(view is UIScrollView), !String(describing: type(of: view)).contains("HostingView") { host = view.superview }
        guard let host else { return }
        let existing = host.interactions.compactMap { $0 as? AreaMenuInteraction }.first
        let interaction = existing ?? {
            let dispatcher = AreaMenuDispatcher()
            let interaction = AreaMenuInteraction(delegate: dispatcher)
            interaction.dispatcher = dispatcher
            host.addInteraction(interaction)
            return interaction
        }()
        interaction.dispatcher?.marks.add(self)
    }
}

/// Keeps its delegate alive (an interaction holds it weakly).
private final class AreaMenuInteraction: UIContextMenuInteraction {
    var dispatcher: AreaMenuDispatcher?
}

private final class AreaMenuDispatcher: NSObject, UIContextMenuInteractionDelegate {
    let marks = NSHashTable<AreaMenuMark>.weakObjects()
    private weak var held: AreaMenuMark?

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let host = interaction.view else { return nil }
        // The mark under the finger; between small neighbors (a grid of days), the nearest within reach.
        let reach: CGFloat = 4
        let candidates = marks.allObjects.filter { $0.window != nil && $0.preview != nil }.map { mark -> (AreaMenuMark, CGRect) in
            (mark, mark.convert(mark.bounds, to: host))
        }.filter { $0.1.insetBy(dx: -reach, dy: -reach).contains(location) }
        guard let mark = candidates.min(by: { distance(from: location, to: $0.1) < distance(from: location, to: $1.1) })?.0,
              let preview = mark.preview, let menu = mark.menu else { return nil }
        held = mark
        return UIContextMenuConfiguration(identifier: nil, previewProvider: preview, actionProvider: { _ in menu() })
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(point.x - rect.midX, point.y - rect.midY)
    }

    /// The preview rises from the held view's place, not from the whole scroll view.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
                                highlightPreviewForItemWithIdentifier identifier: NSCopying) -> UITargetedPreview? {
        targeted()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
                                dismissalPreviewForItemWithIdentifier identifier: NSCopying) -> UITargetedPreview? {
        targeted()
    }

    private func targeted() -> UITargetedPreview? {
        guard let held, held.window != nil else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        return UITargetedPreview(view: held, parameters: parameters)
    }

    /// A tap on the preview: what it previews, once the menu has gone (it may bring up a sheet).
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                                animator: UIContextMenuInteractionCommitAnimating) {
        guard let commit = held?.commit else { return }
        animator.preferredCommitStyle = .dismiss
        animator.addCompletion { commit() }
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
            if let songs = summary.songs, !songs.isEmpty {
                SongList(songs: songs)
            }
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
