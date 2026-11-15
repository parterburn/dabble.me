import SwiftUI

/// An entry's photo (or collage), or a "processing" placeholder while the server is still
/// converting it. The server reports `image_processing` from the moment the job is queued.
struct EntryPhoto: View {
    enum Size { case thumbnail, full }

    let url: URL?
    let isProcessing: Bool
    var size: Size = .full
    /// The entry's day, for the "3 years ago" band on a shared photo.
    var day: JournalDay? = nil
    /// The full photo's corners: square where it runs to the edges of a card that rounds them
    /// itself (an open entry's well).
    var cornerRadius: CGFloat = 12

    var body: some View {
        if isProcessing {
            placeholder
        } else if let url {
            switch size {
            case .thumbnail:
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: appIcon("slab-image").foregroundStyle(.secondary)
                    default: Color.secondary.opacity(0.12)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 8))
            case .full:
                FullEntryPhoto(url: url, day: day, cornerRadius: cornerRadius)
                    .id(url)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size == .full ? cornerRadius : 8)
                .fill(Color.secondary.opacity(0.12))
            if size == .full {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Processing photos…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Runs in the background; okay to leave.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: size == .thumbnail ? 56 : nil, height: size == .full ? 220 : 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photos processing")
    }
}

/// An entry's photo as a small square beside a few lines of it (On This Day under an entry, the
/// Playlist): there to say the day has a photo, not to be looked at closely.
struct EntryThumbnail: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            case .failure: appIcon("slab-image").foregroundStyle(.secondary)
            default: Color.clear
            }
        }
            .frame(width: 64, height: 64)
            .background(Color.secondary.opacity(0.12))
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

/// Tap to view full screen (pinch/double-tap to zoom); long-press to Save or Share.
private struct FullEntryPhoto: View {
    @State private var photo: RemotePhoto
    @State private var showingViewer = false
    @State private var saveResult: PhotoSaveResult?
    @Namespace private var zoom
    private let cornerRadius: CGFloat

    init(url: URL, day: JournalDay?, cornerRadius: CGFloat = 12) {
        _photo = State(initialValue: RemotePhoto(url: url, day: day))
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let image = photo.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if photo.failed {
                Button {
                    Task { await photo.load() }
                } label: {
                    Label("Photo unavailable. Tap to retry.", icon: "slab-image")
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
                .foregroundStyle(.secondary)
            } else {
                Color.secondary.opacity(0.12).frame(height: 240)
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .contentShape(.rect(cornerRadius: cornerRadius))
        .matchedTransitionSource(id: "photo", in: zoom)
        .onTapGesture { if photo.image != nil { showingViewer = true } }
        .contextMenu {
            PhotoMenu(photo: photo, saveResult: $saveResult)
        }
        .fullScreenCover(isPresented: $showingViewer) {
            PhotoViewer(photo: photo)
                .navigationTransition(.zoom(sourceID: "photo", in: zoom))
        }
        .alert(saveResult?.message ?? "", isPresented: .present($saveResult)) {
            Button("OK", role: .cancel) {}
        }
        .accessibilityLabel("Entry photo")
        .accessibilityHint("Double-tap to view full screen. Touch and hold for options.")
        .accessibilityAddTraits(.isButton)
        .task { await photo.load() }
    }
}
