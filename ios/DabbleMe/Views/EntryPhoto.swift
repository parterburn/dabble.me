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
                FullEntryPhoto(url: url, day: day)
                    .id(url)
            }
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

/// Tap to view full screen (pinch/double-tap to zoom); long-press to Save or Share.
private struct FullEntryPhoto: View {
    @State private var photo: RemotePhoto
    @State private var showingViewer = false
    @State private var saveResult: PhotoSaveResult?
    @Namespace private var zoom

    init(url: URL, day: JournalDay?) {
        _photo = State(initialValue: RemotePhoto(url: url, day: day))
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
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
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
