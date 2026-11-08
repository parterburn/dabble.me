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
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Open", systemImage: "arrow.up.forward.app") { open() }
        } preview: {
            // Previews are hosted outside this view's environment, so hand the model over.
            EntryPreview(summary: summary).environment(model)
        }
    }
}

/// The preview shown on long-press: the date, the start of the entry and its photo. Shows the
/// timeline excerpt right away and the full text once it loads.
struct EntryPreview: View {
    let summary: EntrySummary
    @Environment(AppModel.self) private var model
    @State private var entry: EntryDetail?
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.day?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()) ?? summary.date)
                .font(.headline)
            if let document = entry?.document {
                DocumentText(blocks: document, font: .system(size: bodySize, design: .serif), scale: 1, bodySize: bodySize)
                    .lineLimit(14)
            } else {
                Text(entry.map { AttributedString.journal($0.bodyText) } ?? AttributedString(summary.excerpt))
                    .font(.system(size: bodySize, design: .serif))
                    .lineLimit(14)
            }
            if summary.imageURL != nil, !summary.imageProcessing {
                AsyncImage(url: summary.thumbnailURL(width: 700)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 10))
            }
        }
        .padding()
        .frame(width: 340, alignment: .topLeading)
        .frame(maxHeight: 520, alignment: .top)
        .task { entry = try? await model.entry(id: summary.id) }
    }
}
