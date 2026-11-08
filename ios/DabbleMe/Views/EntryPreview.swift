import SwiftUI

extension View {
    /// Long-press to preview an entry (Peek), with Open to go to it.
    func entryPreview(_ summary: EntrySummary, open: @escaping () -> Void) -> some View {
        modifier(EntryPreviewMenu(summary: summary, open: open))
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
            .font(.system(size: bodySize, design: .serif))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
