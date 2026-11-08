import SwiftUI

/// An entry's photo (or collage), or a "processing" placeholder while the server is still
/// converting it. The server reports `image_processing` from the moment the job is queued.
struct EntryPhoto: View {
    enum Size { case thumbnail, full }

    let url: URL?
    let isProcessing: Bool
    var size: Size = .full

    var body: some View {
        if isProcessing {
            placeholder
        } else if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    if size == .thumbnail {
                        image.resizable().scaledToFill()
                    } else {
                        image.resizable().scaledToFit()
                    }
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: size == .full ? 120 : nil)
                default:
                    Color.secondary.opacity(0.12)
                        .frame(height: size == .full ? 240 : nil)
                }
            }
            .modifier(Frame(size: size))
            .accessibilityLabel("Entry photo")
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size == .full ? 12 : 8)
                .fill(Color.secondary.opacity(0.12))
            if size == .full {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Processing photos…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("They're saved. This usually takes under a minute.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(height: size == .full ? 220 : nil)
        .modifier(Frame(size: size))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photos processing")
    }

    private struct Frame: ViewModifier {
        let size: Size

        func body(content: Content) -> some View {
            switch size {
            case .thumbnail:
                content.frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 8))
            case .full:
                content.clipShape(.rect(cornerRadius: 12))
            }
        }
    }
}
