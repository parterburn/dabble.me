import SwiftUI

/// Journal > Photos: every entry with a photo, newest first. Tap one to open that day.
struct PhotoGridView: View {
    /// Opens an entry (long-press → Open).
    var open: (EntryRoute) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var entries: [EntrySummary] = []
    @State private var nextPage: Int? = 1
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Group {
            if entries.isEmpty {
                if let error {
                    ContentUnavailableView {
                        Label("Couldn't load your photos", icon: "slab-images")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await load(reset: true) } }
                    }
                } else if isLoading || nextPage != nil {
                    ProgressView()
                } else {
                    ContentUnavailableView {
                        Label("No photos yet", icon: "slab-images")
                    } description: {
                        Text("Entries with photos will show up here.")
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 220 : 110), spacing: 2)], spacing: 2) {
                        ForEach(entries) { entry in
                            NavigationLink(value: EntryRoute(id: entry.id)) {
                                PhotoCell(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .entryPreview(entry) { open(EntryRoute(id: entry.id)) }
                            .task {
                                if entry.id == entries.last?.id { await load(reset: false) }
                            }
                        }
                    }
                    if nextPage != nil {
                        ProgressView().padding()
                    }
                }
            }
        }
        .refreshable { await load(reset: true) }
        .task { if entries.isEmpty { await load(reset: true) } }
        // A photo that was still processing is ready: its square shows it.
        .onChange(of: model.photosFinished) { Task { await refreshNewest() } }
    }

    /// The newest page again, laid over what's loaded (a photo just finished is among the
    /// latest), so someone far down the grid keeps their place and the pages under it.
    private func refreshNewest() async {
        guard !entries.isEmpty, let result = try? await model.photoEntries(page: 1) else { return }
        let fresh = Dictionary(result.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(entries.map(\.id))
        entries = result.entries.filter { !known.contains($0.id) } + entries.map { fresh[$0.id] ?? $0 }
    }

    private func load(reset: Bool) async {
        let page = reset ? 1 : nextPage
        guard let page, !isLoading || reset else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await model.photoEntries(page: page)
            entries = reset ? result.entries : entries + result.entries.filter { new in !entries.contains { $0.id == new.id } }
            nextPage = result.nextPage
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
            if reset { nextPage = nil }
        }
    }
}

private struct PhotoCell: View {
    let entry: EntrySummary

    var body: some View {
        Color.secondary.opacity(0.12)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if entry.imageProcessing {
                    ProgressView()
                } else if let url = entry.thumbnailURL(width: 400) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure: appIcon("slab-image").foregroundStyle(.secondary)
                        default: EmptyView()
                        }
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(entry.day?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(6)
            }
            .clipped()
            .contentShape(.rect)
            .accessibilityElement()
            .accessibilityLabel("Photo from \(entry.day?.long ?? entry.date)")
            .accessibilityAddTraits(.isButton)
    }
}

extension EntrySummary {
    /// A smaller copy of the photo through Cloudflare image resizing when the URL supports it
    /// (production photos are served via /cdn-cgi/image/), else the original.
    func thumbnailURL(width: Int) -> URL? {
        Self.thumbnailURL(imageUrl, width: width)
    }

    static func thumbnailURL(_ imageUrl: String?, width: Int) -> URL? {
        guard let imageUrl else { return nil }
        // Whatever options the address came with (the server's are "quality=100"), as the web does.
        let resized = imageUrl.replacingOccurrences(of: #"/cdn-cgi/image/[^/]+/"#,
                                                    with: "/cdn-cgi/image/width=\(width),quality=85,fit=cover/",
                                                    options: .regularExpression)
        return URL(string: resized)
    }
}
