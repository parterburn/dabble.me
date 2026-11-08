import SwiftUI

/// One entry. Pull down at the top for the next (newer) day with an entry, pull up at the
/// bottom for the previous one, like pulling the days into view. Pinch to change text size.
struct EntryDetailView: View {
    let entryID: Int

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var currentID: Int?
    @State private var entry: EntryDetail?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var pull = Pull.none
    @State private var arrivalEdge = Edge.bottom
    @State private var isMoving = false
    @State private var pinchStart: ReadingTextSize?
    @State private var textSizeHUD: String?
    @State private var hideHUD: Task<Void, Never>?
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard

    private var id: Int { currentID ?? entryID }

    /// How far past the top/bottom the reader has pulled; `armed` means releasing will move.
    enum Pull: Equatable {
        case none
        case newer(armed: Bool)
        case older(armed: Bool)
    }

    private static let pullThreshold: CGFloat = 90

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    EntryBody(entry: entry)
                        .padding()
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                        .simultaneousGesture(pinchToResize)
                        .id(entry.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: arrivalEdge).combined(with: .opacity),
                            removal: .move(edge: arrivalEdge == .top ? .bottom : .top).combined(with: .opacity)
                        ))
                }
                .scrollBounceBehavior(.always)
                .onScrollGeometryChange(for: Pull.self, of: Self.pull(for:)) { _, newValue in
                    pull = newValue
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    if oldPhase == .interacting, newPhase != .interacting { releasePull(from: entry) }
                }
                .overlay(alignment: .top) {
                    if case .newer(let armed) = pull {
                        PullHint(text: hintText(for: entry.nextEntry, armed: armed, newer: true), systemImage: "arrow.down", armed: armed)
                    }
                }
                .overlay(alignment: .bottom) {
                    if case .older(let armed) = pull {
                        PullHint(text: hintText(for: entry.previousEntry, armed: armed, newer: false), systemImage: "arrow.up", armed: armed)
                            .padding(.bottom, 70)
                    }
                }
                .overlay {
                    if let textSizeHUD {
                        Text(textSizeHUD)
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: .capsule)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: textSizeHUD)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Couldn't load this entry", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(entry?.day?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let entry {
                ToolbarItem(placement: .primaryAction) { menu(for: entry) }
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Entry", role: .destructive) { Task { await delete() } }
        } message: {
            Text("This can't be undone.")
        }
        .sheet(isPresented: $editing) {
            if let entry {
                ComposeView(mode: .edit(entry)) { self.entry = $0 }
            }
        }
        .alert("Something went wrong", isPresented: .present($actionError)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pull.isArmed) { _, armed in armed }
        .sensoryFeedback(.selection, trigger: textSize)
        .disabled(isDeleting)
        .task { await load() }
        .task(id: entry?.imageProcessing) {
            // Swap the placeholder for the finished photo/collage as soon as it's ready.
            while entry?.imageProcessing == true, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await load()
            }
        }
    }

    private func menu(for entry: EntryDetail) -> some View {
        Menu {
            if model.me?.canEdit == true {
                if entry.document != nil {
                    Button("Edit", systemImage: "pencil") { editing = true }
                } else {
                    // Formatting the app can't represent (styles, quotes, AI replies) stays web-only so nothing gets lost.
                    Button("Edit on dabble.me", systemImage: "safari") { openURL(entry.webUrl) }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } else {
                Button("Open on dabble.me", systemImage: "safari") { openURL(entry.webUrl) }
            }
        } label: {
            Label("Entry Actions", systemImage: "ellipsis.circle")
        }
    }

    // MARK: - Pulling between days

    private static func pull(for geometry: ScrollGeometry) -> Pull {
        let top = -(geometry.contentOffset.y + geometry.contentInsets.top)
        let maxOffset = max(-geometry.contentInsets.top,
                            geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height)
        let bottom = geometry.contentOffset.y - maxOffset
        if top > 24 { return .newer(armed: top > pullThreshold) }
        if bottom > 24 { return .older(armed: bottom > pullThreshold) }
        return .none
    }

    private func hintText(for neighbour: EntryNeighbour?, armed: Bool, newer: Bool) -> String {
        guard let day = neighbour?.day else { return newer ? "This is your newest entry" : "This is your first entry" }
        let date = day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
        return armed ? "Release for \(date)" : "Pull for \(date)"
    }

    private func releasePull(from entry: EntryDetail) {
        switch pull {
        case .newer(armed: true): move(to: entry.nextEntry, arrivingFrom: .top)
        case .older(armed: true): move(to: entry.previousEntry, arrivingFrom: .bottom)
        default: break
        }
    }

    private func move(to neighbour: EntryNeighbour?, arrivingFrom edge: Edge) {
        guard let neighbour, !isMoving else { return }
        isMoving = true
        Task {
            defer { isMoving = false }
            do {
                let next = try await model.entry(id: neighbour.id)
                arrivalEdge = edge
                withAnimation(.snappy(duration: 0.35)) {
                    currentID = next.id
                    entry = next
                }
            } catch is CancellationError {
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    // MARK: - Pinch to resize text

    /// Each ~25% of pinch moves one text size step (Small … Largest).
    private var pinchToResize: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.04)
            .onChanged { value in
                let start = pinchStart ?? textSize
                if pinchStart == nil { pinchStart = start }
                let steps = Int((log(value.magnification) / log(1.25)).rounded(.towardZero))
                let index = min(max(start.rawValue + steps, 0), ReadingTextSize.allCases.count - 1)
                if let size = ReadingTextSize(rawValue: index), size != textSize { textSize = size }
                showHUD()
            }
            .onEnded { _ in
                pinchStart = nil
                hideHUD?.cancel()
                hideHUD = Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    guard !Task.isCancelled else { return }
                    textSizeHUD = nil
                }
            }
    }

    private func showHUD() {
        hideHUD?.cancel()
        textSizeHUD = "Text Size: \(textSize.label)"
    }

    // MARK: - Loading

    private func load() async {
        do {
            entry = try await model.entry(id: id)
            loadError = nil
        } catch is CancellationError {
        } catch {
            if entry == nil { loadError = error.localizedDescription } else { actionError = error.localizedDescription }
        }
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await model.deleteEntry(id: id)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private extension EntryDetailView.Pull {
    var isArmed: Bool {
        switch self {
        case .newer(let armed), .older(let armed): armed
        case .none: false
        }
    }
}

private struct PullHint: View {
    let text: String
    let systemImage: String
    let armed: Bool

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(armed ? .semibold : .regular))
            .foregroundStyle(armed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: .capsule)
            .padding(.top, 8)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: armed)
    }
}

private struct EntryBody: View {
    let entry: EntryDetail
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17

    private var bodyFont: Font { .system(size: bodySize * textSize.scale, design: .serif) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(entry.day?.long ?? entry.date)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            if let document = entry.document {
                Text(RichText.linkingHashtags(in: RichText.displayString(from: document)))
                    .font(bodyFont)
                    .lineSpacing(5 * textSize.scale)
                    .textSelection(.enabled)
            } else if !entry.bodyText.isEmpty {
                Text(RichText.linkingHashtags(in: AttributedString.journal(entry.bodyText)))
                    .font(bodyFont)
                    .lineSpacing(5 * textSize.scale)
                    .textSelection(.enabled)
            }

            if !entry.songs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Songs")
                        .font(.headline)
                    ForEach(entry.songs, id: \.self) { song in
                        Link(destination: song.spotifyUrl) {
                            Label(song.label, systemImage: "music.note")
                        }
                    }
                }
            }

            // Text first: Dabble Me is about the writing; photos follow it.
            if entry.imageProcessing || entry.imageURL != nil {
                EntryPhoto(url: entry.imageURL, isProcessing: entry.imageProcessing)
            }
        }
    }
}

extension AttributedString {
    /// Entry text comes from the server as light Markdown (bold, italics, links); render it,
    /// falling back to plain text if it doesn't parse.
    static func journal(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
