import Photos
import SwiftUI
import UIKit

/// Loads an entry photo once and keeps both the decoded image (for display and sharing)
/// and the original bytes (so "Save to Photos" keeps full quality).
@MainActor
@Observable
final class RemotePhoto {
    let url: URL
    private(set) var image: UIImage?
    private(set) var data: Data?
    private(set) var failed = false

    init(url: URL) {
        self.url = url
    }

    func load() async {
        guard image == nil else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = await Task.detached(operation: { UIImage(data: data)?.preparingForDisplay() }).value
            else { throw URLError(.cannotDecodeContentData) }
            self.data = data
            self.image = image
            failed = false
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }
}

enum PhotoSaveResult: Identifiable {
    case saved, denied, failed

    var id: Self { self }

    var message: String {
        switch self {
        case .saved: "Saved to Photos."
        case .denied: "Dabble Me doesn't have permission to add photos. You can allow it in Settings → Dabble Me → Photos."
        case .failed: "The photo couldn't be saved. Please try again."
        }
    }
}

enum PhotoActions {
    /// Uses add-only access: Dabble Me never asks to read your photo library.
    static func save(_ data: Data) async -> PhotoSaveResult {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
    }
}

/// Long-press actions shared by the inline photo and the full-screen viewer.
struct PhotoMenu: View {
    let photo: RemotePhoto
    @Binding var saveResult: PhotoSaveResult?

    var body: some View {
        if let image = photo.image, let data = photo.data {
            Button {
                Task { saveResult = await PhotoActions.save(data) }
            } label: {
                Label("Save to Photos", icon: "slab-arrow-down-to-line")
            }
            ShareLink(item: Image(uiImage: image), preview: SharePreview("Photo", image: Image(uiImage: image))) {
                Label("Share…", icon: "slab-arrow-up-from-line")
            }
            Button {
                UIPasteboard.general.image = image
            } label: {
                Label("Copy", icon: "slab-copy")
            }
        } else {
            Text("Loading photo…")
        }
    }
}

/// Full-screen photo: pinch or double-tap to zoom, swipe down or tap ✕ to close.
struct PhotoViewer: View {
    let photo: RemotePhoto
    @Environment(\.dismiss) private var dismiss
    @State private var saveResult: PhotoSaveResult?
    @State private var dragOffset: CGFloat = 0
    @State private var isZoomed = false

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(abs(dragOffset) / 400, 0.6))
                .ignoresSafeArea()

            if let image = photo.image {
                ZoomableImage(image: image, isZoomed: $isZoomed)
                    .ignoresSafeArea()
                    .offset(y: dragOffset)
                    .gesture(isZoomed ? nil : dismissDrag)
                    .accessibilityLabel("Entry photo")
                    .accessibilityHint("Pinch or double-tap to zoom")
            } else if photo.failed {
                Label("Photo unavailable", icon: "slab-image").foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .top) { toolbar }
        .statusBarHidden()
        .alert(saveResult?.message ?? "", isPresented: .present($saveResult)) {
            Button("OK", role: .cancel) {}
        }
        .task { await photo.load() }
    }

    private var toolbar: some View {
        HStack {
            Button { dismiss() } label: { Label("Close", icon: "slab-close") }
            Spacer()
            if photo.image != nil {
                Menu {
                    PhotoMenu(photo: photo, saveResult: $saveResult)
                } label: {
                    Label("Photo Actions", systemImage: "ellipsis")
                }
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(.white.opacity(0.25))
        .padding(.horizontal)
        .opacity(dragOffset == 0 ? 1 : 0)
    }

    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation.height }
            .onEnded { value in
                if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 300 {
                    dismiss()
                } else {
                    withAnimation(.spring) { dragOffset = 0 }
                }
            }
    }
}

/// UIScrollView-backed zooming: smooth pinch, double-tap to zoom in/out, and panning when zoomed.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    @Binding var isZoomed: Bool

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4
        scrollView.minimumZoomScale = 1
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isZoomed: $isZoomed)
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        let isZoomed: Binding<Bool>

        init(isZoomed: Binding<Bool>) {
            self.isZoomed = isZoomed
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > 1.01
            if isZoomed.wrappedValue != zoomed { isZoomed.wrappedValue = zoomed }
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
                scrollView.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
            }
        }
    }
}
