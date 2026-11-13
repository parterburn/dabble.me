import AVFoundation
import SwiftUI
import WebKit

/// Journal > Playlist: every entry with a song, newest first, by month. Each row is the day, a
/// few lines of the entry in smaller type (no photo), and its songs, always shown. Tap a song to
/// play it in Spotify's own player, docked at the bottom (a preview, or the whole song for someone
/// signed in to Spotify there; swipe it left to put it away); tap the row to open the entry.
struct PlaylistView: View {
    var open: (EntryRoute) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @State private var entries: [EntrySummary] = []
    @State private var nextPage: Int? = 1
    @State private var isLoading = false
    @State private var error: String?
    /// The song in the player.
    @State private var playing: Song?
    /// Counts the taps on Play: each starts the player's song.
    @State private var plays = 0

    /// The loaded entries by month, newest first.
    private var months: [(key: String, title: String, entries: [EntrySummary])] {
        var result: [(key: String, title: String, entries: [EntrySummary])] = []
        for entry in entries {
            let key = entry.day?.monthKey ?? String(entry.date.prefix(7))
            if result.last?.key == key {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append((key, entry.day?.monthTitle ?? key, [entry]))
            }
        }
        return result
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                if let error {
                    ContentUnavailableView {
                        Label("Couldn't load your playlist", icon: "slab-music")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { Task { await load(reset: true) } }
                    }
                } else if isLoading || nextPage != nil {
                    ProgressView()
                } else {
                    ContentUnavailableView {
                        Label("No songs yet", icon: "slab-music")
                    } description: {
                        Text("Paste a Spotify song link into an entry and it will show up here.")
                    }
                }
            } else {
                List {
                    ForEach(months, id: \.key) { month in
                        Section {
                            ForEach(month.entries) { entry in
                                PlaylistRow(entry: entry, playing: playing, play: toggle) { open(EntryRoute(id: entry.id)) }
                                    .entryPreview(entry) { open(EntryRoute(id: entry.id)) }
                                    .timelineRowLayout()
                                    .task {
                                        if entry.id == entries.last?.id { await load(reset: false) }
                                    }
                            }
                        } header: {
                            MonthHeader(title: month.title)
                        }
                    }
                    if nextPage != nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let playing { SongPlayerBar(song: playing, plays: plays) { self.playing = nil } }
        }
        .animation(.snappy(duration: 0.25), value: playing)
        .refreshable { await load(reset: true) }
        .task { if entries.isEmpty { await load(reset: true) } }
    }

    /// Plays a song, or stops the one that's playing when it's tapped again.
    private func toggle(_ song: Song) {
        if playing == song {
            playing = nil
        } else {
            plays += 1
            playing = song
        }
    }

    private func load(reset: Bool) async {
        let page = reset ? 1 : nextPage
        guard let page, !isLoading || reset else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await model.songEntries(page: page)
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

/// One entry in the Playlist: laid out like a Journal row (the date in its own column), with a
/// shorter, smaller preview and the songs under it.
private struct PlaylistRow: View {
    let entry: EntrySummary
    let playing: Song?
    let play: (Song) -> Void
    let open: () -> Void
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif

    /// The entry's words without its song links (the songs are right under it).
    private var preview: String {
        entry.excerpt
            .replacingOccurrences(of: #"https?://open\.spotify\.com/\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(entry.day?.weekdayShort.uppercased() ?? "")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.day?.dayNumber ?? "")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 42)
            .padding(.top, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.day?.long ?? entry.date)
            VStack(alignment: .leading, spacing: 10) {
                if !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: bodySize * textSize.scale * 0.88, design: fontStyle.design))
                        .lineSpacing(3)
                        .lineLimit(3)
                        .foregroundStyle(.primary.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(entry.songs ?? [], id: \.self) { song in
                    SongButton(song: song, isPlaying: playing == song) { play(song) }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .accessibilityAction(named: "Open Entry", open)
    }
}

/// A song with its play button (stop, while it's the one playing). Touch and hold for Spotify.
private struct SongButton: View {
    let song: Song
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
                Text(song.label)
                    .font(.subheadline.weight(isPlaying ? .semibold : .regular))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color("AccentColor"))
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .contextMenu {
            Link(destination: song.spotifyUrl) { Label("Open in Spotify", icon: "slab-external-link") }
        }
        .accessibilityLabel(song.label)
        .accessibilityValue(isPlaying ? "Playing" : "")
        .accessibilityHint(isPlaying ? "Stops it" : "Plays it")
        .accessibilityAddTraits(isPlaying ? .isSelected : [])
    }
}

/// Spotify's player for a song, docked above the tab bar: on the Playlist, and under an entry that
/// has a song. It swipes like a row of a list: to the left, Open in Spotify and an X that puts
/// the player away (keep swiping and it goes); to the right, under an entry, the Playlist (keep
/// swiping to go there).
struct SongPlayerBar: View {
    let song: Song
    /// Counts the times the song was asked to play. Each new one starts it; with none (an entry
    /// just opened) the player waits for its own play button.
    var plays = 0
    /// A swipe to the right offers the Playlist (nil on the Playlist itself).
    var openPlaylist: (() -> Void)?
    let close: () -> Void
    @Environment(\.openURL) private var openURL
    /// Where the player rests (0, or moved aside to show its actions), and the swipe under way.
    @State private var rest: CGFloat = 0
    @State private var drag: CGFloat = 0
    @State private var isLeaving = false
    /// A swipe is under way (and hasn't been let go of yet).
    @State private var isSwiping = false

    private static let action: CGFloat = 58
    /// Past this, letting go does the swipe's own action (the X, the Playlist).
    private static let commit: CGFloat = 190
    private var trailing: CGFloat { Self.action * 2 }
    private var leading: CGFloat { openPlaylist == nil ? 0 : Self.action }
    /// The player's place: it follows the finger, more stiffly past where its actions end.
    private var x: CGFloat {
        if isLeaving { return rest }
        let wanted = rest + drag
        return openPlaylist == nil ? min(wanted, 0) : wanted
    }
    private var isArmed: Bool { x < -Self.commit || x > Self.commit }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if let openPlaylist {
                    action("slab-music", "Open Playlist", prominent: x > Self.commit, action: openPlaylist)
                        .opacity(x > 4 ? 1 : 0)
                }
                Spacer(minLength: 0)
                Group {
                    action("slab-external-link", "Open in Spotify", prominent: false) {
                        openURL(song.spotifyUrl)
                        settle(at: 0)
                    }
                    action("slab-close", "Hide Player", prominent: x < -Self.commit, action: putAway)
                }
                .opacity(x < -4 ? 1 : 0)
            }
            SpotifyPlayer(trackID: song.trackID ?? "", plays: plays, panned: panned)
                .frame(height: SpotifyPlayer.height)
                .clipShape(.rect(cornerRadius: 12))
                .offset(x: x)
                .accessibilityLabel("Spotify player, \(song.label)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        // Around the web view (which reports its own drags, above): the actions, once showing.
        .simultaneousGesture(DragGesture(minimumDistance: 15).onChanged { value in
            if abs(value.translation.width) > abs(value.translation.height) { panned(value.translation.width, velocity: 0, ended: false) }
        }.onEnded { value in
            panned(value.translation.width, velocity: value.velocity.width, ended: true)
        })
        .sensoryFeedback(.impact(weight: .light), trigger: isArmed) { _, armed in armed }
        .accessibilityAction(named: "Hide Player", putAway)
        .accessibilityAction(named: "Open in Spotify") { openURL(song.spotifyUrl) }
        .accessibilityActions {
            if let openPlaylist { Button("Open Playlist", action: openPlaylist) }
        }
        // Heard with the ringer switched off too, as music is (the player's own button included).
        .onAppear { try? AVAudioSession.sharedInstance().setCategory(.playback) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// A round button behind the player; the one a full swipe would press fills in.
    private func action(_ icon: String, _ label: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            appIcon(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 44, height: 44)
                .background(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.08)), in: .circle)
                .frame(width: Self.action)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A swipe on the player, from the web view or around it: it follows, and on letting go either
    /// does the swipe's action (far enough, or flicked), rests with its actions showing, or closes.
    private func panned(_ translation: CGFloat, velocity: CGFloat, ended: Bool) {
        guard !isLeaving else { return }
        guard ended else { isSwiping = true; drag = translation; return }
        // One swipe is let go of once, though both the web view and the bar around it say so:
        // counted twice, it would land twice as far, or spring back.
        guard isSwiping else { return }
        isSwiping = false
        let end = rest + drag
        drag = 0
        rest = end // from where the finger left it
        if end < -Self.commit || (velocity < -700 && end < -60) {
            putAway()
        } else if let openPlaylist, end > Self.commit || (velocity > 700 && end > 60) {
            settle(at: 0)
            openPlaylist()
        } else if end < -trailing / 2 {
            settle(at: -trailing)
        } else if leading > 0, end > leading / 2 {
            settle(at: leading)
        } else {
            settle(at: 0)
        }
    }

    private func settle(at place: CGFloat) {
        withAnimation(.snappy(duration: 0.25)) { rest = place }
    }

    /// Slides off to the left, then goes (which stops the music).
    private func putAway() {
        guard !isLeaving else { return }
        isLeaving = true
        withAnimation(.easeIn(duration: 0.2)) { rest = -1400 } completion: { close() }
    }
}

/// Spotify's embedded player (its iFrame API) for one track. It starts the song when asked to
/// (`plays`), and otherwise shows it ready to play. What plays is up to Spotify: a preview, or the
/// whole song for someone signed in to Spotify in it.
struct SpotifyPlayer: UIViewRepresentable {
    static let height: CGFloat = 80
    let trackID: String
    var plays = 0
    /// A sideways drag on the player (the web view takes touches for itself): how far, how fast
    /// when let go, and whether it has been.
    var panned: (_ translation: CGFloat, _ velocity: CGFloat, _ ended: Bool) -> Void = { _, _, _ in }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = [] // the tap on Play was the action
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.backgroundColor = .clear
        view.navigationDelegate = context.coordinator
        // The web view takes touches for itself, so the drag that moves the player aside is its own.
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.panned = panned
        if coordinator.trackID != trackID {
            // A song that comes with a new request to play starts; one that's only shown waits.
            let starts = coordinator.plays != plays
            coordinator.trackID = trackID
            coordinator.plays = plays
            view.loadHTMLString(Self.page(for: trackID, autoplay: starts), baseURL: AppConfig.productionURL)
        } else if coordinator.plays != plays {
            coordinator.plays = plays
            view.evaluateJavaScript("window.dabblePlay && window.dabblePlay()") // kept if the player isn't ready yet
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.loadHTMLString("", baseURL: nil) // stops the music when the player closes
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// `trackID` is letters and digits only (`Song.trackID`).
    static func page(for trackID: String, autoplay: Bool) -> String {
        """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;background:transparent;overflow:hidden}</style>
        <div id="player"></div>
        <script src="https://open.spotify.com/embed/iframe-api/v1" async></script>
        <script>
        // A tap on Play can come before Spotify's player is there, or before it's ready: it's kept
        // until then.
        var wants = \(autoplay), ready = false, player = null;
        window.dabblePlay = function () { if (ready) { player.play(); } else { wants = true; } };
        window.onSpotifyIframeApiReady = function (api) {
          api.createController(document.getElementById('player'),
            { uri: 'spotify:track:\(trackID)', width: '100%', height: \(Int(height)) },
            function (controller) {
              player = controller;
              controller.addListener('ready', function () { ready = true; if (wants) { controller.play(); } });
            });
        };
        </script>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var trackID: String?
        var plays = 0
        var panned: (CGFloat, CGFloat, Bool) -> Void = { _, _, _ in }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            // Measured against the window: the player itself moves with the drag.
            let translation = recognizer.translation(in: nil).x
            switch recognizer.state {
            case .changed: panned(translation, 0, false)
            case .ended, .cancelled, .failed: panned(translation, recognizer.velocity(in: nil).x, true)
            default: break
            }
        }

        /// Sideways drags only: up and down is the page's.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        /// Links in the player (the Spotify logo, the song's page) open outside the app.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated || action.targetFrame == nil, let url = action.request.url else { return .allow }
            await UIApplication.shared.open(url)
            return .cancel
        }
    }
}
