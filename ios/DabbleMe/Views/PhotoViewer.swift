import Photos
import SwiftUI
import UIKit

/// Loads an entry photo once and keeps both the decoded image (for display and sharing)
/// and the original bytes (so "Save to Photos" keeps full quality).
@MainActor
@Observable
final class RemotePhoto {
    let url: URL
    /// The entry's day, for the band on a shared photo ("3 years ago").
    let day: JournalDay?
    private(set) var image: UIImage?
    private(set) var data: Data?
    private(set) var failed = false

    init(url: URL, day: JournalDay? = nil) {
        self.url = url
        self.day = day
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

@MainActor
enum PhotoActions {
    /// Shares the photo as a card: an olive band with the "me" mark and how long ago it was, above
    /// the photo (like Timehop's, without a watermark). Made on the device, only when you share.
    /// Presented from UIKit, after the menu that asked for it has gone: SwiftUI's ShareLink in a
    /// menu over a full-screen cover sometimes did nothing.
    static func share(_ photo: RemotePhoto) async {
        guard let image = photo.image else { return }
        let label = photo.day?.shareLabel(to: JournalDay(localDate: .now))
        let card = label.map { ShareCard.render(image, label: $0) } ?? image
        // As a JPEG file: the share sheet then shows the card itself and a sensible name.
        let file = FileManager.default.temporaryDirectory.appending(path: "Dabble Me – \(label ?? "Photo").jpg")
        let item: Any
        if let data = card.jpegData(compressionQuality: 0.9), (try? data.write(to: file, options: .atomic)) != nil {
            item = file
        } else {
            item = card
        }
        try? await Task.sleep(for: .milliseconds(350)) // let a context menu finish closing
        guard var top = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController
        else { return }
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        let sheet = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        sheet.popoverPresentationController?.permittedArrowDirections = []
        top.present(sheet, animated: true)
    }

    /// Uses add-only access: Dabble Me never asks to read your photo library. Not on the main
    /// actor: Photos runs the change block on its own queue, and a main-actor closure there traps.
    nonisolated static func save(_ data: Data) async -> PhotoSaveResult {
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
        // No Copy: the share sheet has it.
        if photo.image != nil, let data = photo.data {
            Button {
                Task { saveResult = await PhotoActions.save(data) }
            } label: {
                Label("Save to Photos", icon: "slab-arrow-down-to-line")
            }
            Button {
                Task { await PhotoActions.share(photo) }
            } label: {
                Label("Share…", icon: "slab-arrow-up-from-line")
            }
        } else {
            Text("Loading photo…")
        }
    }
}

/// Full-screen photo, under the band it's shared with (how long ago it was): pinch or double-tap
/// to zoom, swipe down or tap ✕ to close. Save keeps the original photo, without the band.
struct PhotoViewer: View {
    let photo: RemotePhoto
    @Environment(\.dismiss) private var dismiss
    @State private var saveResult: PhotoSaveResult?
    @State private var dragOffset: CGFloat = 0
    @State private var isZoomed = false
    /// The photo under its band ("3 years ago"), as it's shared. Save still saves the original.
    @State private var card: UIImage?

    /// "3 years ago", when the photo's day is known.
    private var bandLabel: String? { photo.day?.shareLabel(to: JournalDay(localDate: .now)) }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(abs(dragOffset) / 400, 0.6))
                .ignoresSafeArea()

            if let image = photo.image, bandLabel != nil, card == nil {
                // Making the band takes a moment on a large photo.
                ProgressView().tint(.white)
                    .task {
                        await Task.yield() // let the spinner show first
                        card = bandLabel.map { ShareCard.render(image, label: $0, maxWidth: 1600) } ?? image
                    }
            } else if let image = card ?? photo.image {
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
        .overlay(alignment: .top) { closeBar }
        .overlay(alignment: .bottom) { actionBar }
        .statusBarHidden()
        .alert(saveResult?.message ?? "", isPresented: .present($saveResult)) {
            Button("OK", role: .cancel) {}
        }
        .task { await photo.load() }
    }

    /// The X at the top right, where it is on the app's other sheets.
    private var closeBar: some View {
        HStack {
            Spacer()
            SheetCloseButton(onDark: true)
        }
        .padding(.horizontal)
        .opacity(dragOffset == 0 ? 1 : 0)
    }

    /// Save and Share, labelled, at the bottom center (as in Photos), rather than a ⋯ menu (which
    /// sometimes didn't open) or bare icons (easy to miss).
    @ViewBuilder
    private var actionBar: some View {
        if photo.image != nil, let data = photo.data {
            HStack(spacing: 12) {
                Button {
                    Task { saveResult = await PhotoActions.save(data) }
                } label: {
                    pill("Save", icon: "slab-arrow-down-to-line")
                }
                .accessibilityLabel("Save to Photos")
                Button {
                    Task { await PhotoActions.share(photo) }
                } label: {
                    pill("Share", icon: "slab-arrow-up-from-line")
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
            .opacity(dragOffset == 0 ? 1 : 0)
        }
    }

    /// White text and icon on a dark translucent capsule, readable over any photo.
    private func pill(_ title: String, icon: String) -> some View {
        // The icon close to its word (a Label leaves more room between them).
        HStack(spacing: 5) {
            appIcon(icon)
            Text(title)
        }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .background(.black.opacity(0.45), in: .capsule)
            .background(.ultraThinMaterial.opacity(0.6), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            .contentShape(.capsule)
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

/// The shared photo's band: the "me" mark and "3 years ago" in semibold white serif on olive,
/// across the top of the photo at its own width.
enum ShareCard {
    @MainActor
    static func render(_ photo: UIImage, label: String, maxWidth: CGFloat = 2400) -> UIImage {
        // Big enough to look sharp anywhere, small enough to share quickly (the viewer asks for less).
        let width = min(photo.size.width * photo.scale, maxWidth)
        let photoHeight = width * photo.size.height / max(photo.size.width, 1)
        let band = (width * 0.11).rounded()
        let card = VStack(spacing: 0) {
            HStack(spacing: band * 0.22) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: band * 0.6, height: band * 0.6)
                    .clipShape(.circle)
                Text(label)
                    .font(.system(size: band * 0.36, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: width, height: band)
            .background(Color("AccentColor"))
            Image(uiImage: photo)
                .resizable()
                .frame(width: width, height: photoHeight)
        }
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage ?? photo
    }
}
