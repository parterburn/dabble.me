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
/// has a song. Swipe it left to put it away; the button beside it opens the song in Spotify.
struct SongPlayerBar: View {
    let song: Song
    /// Counts the times the song was asked to play. Each new one starts it; with none (an entry
    /// just opened) the player waits for its own play button.
    var plays = 0
    let close: () -> Void
    /// Follows the swipe that puts it away.
    @State private var slide: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            SpotifyPlayer(trackID: song.trackID ?? "", plays: plays, swipedLeft: putAway)
                .frame(height: SpotifyPlayer.height)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityLabel("Spotify player, \(song.label)")
            Link(destination: song.spotifyUrl) {
                appIcon("slab-external-link")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.08), in: .circle)
            }
            .accessibilityLabel("Open in Spotify")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .offset(x: slide)
        // Off the web view (which has a swipe of its own, below): around it and on the button.
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { drag in
            if drag.translation.width < -60, abs(drag.translation.height) < 50 { putAway() }
        })
        .accessibilityAction(named: "Hide Player", putAway)
        // Heard with the ringer switched off too, as music is (the player's own button included).
        .onAppear { try? AVAudioSession.sharedInstance().setCategory(.playback) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Slides off to the left, then goes (which stops the music).
    private func putAway() {
        guard slide == 0 else { return }
        withAnimation(.easeIn(duration: 0.2)) { slide = -1400 } completion: { close() }
    }
}

/// Spotify's embedded player (its iFrame API) for one track. It starts the song when asked to
/// (`plays`), and otherwise shows it ready to play. What plays is up to Spotify: a preview, or the
/// whole song for someone signed in to Spotify in it.
struct SpotifyPlayer: UIViewRepresentable {
    static let height: CGFloat = 80
    let trackID: String
    var plays = 0
    var swipedLeft: () -> Void = {}

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
        // The web view takes touches for itself, so the swipe that puts the player away is its own.
        let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swiped))
        swipe.direction = .left
        swipe.delegate = context.coordinator
        view.addGestureRecognizer(swipe)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.swipedLeft = swipedLeft
        if coordinator.trackID != trackID {
            // A song that comes with a new request to play starts; one that's only shown waits.
            let starts = coordinator.plays != plays
            coordinator.trackID = trackID
            coordinator.plays = plays
            view.loadHTMLString(Self.page(for: trackID, autoplay: starts), baseURL: AppConfig.productionURL)
        } else if coordinator.plays != plays {
            coordinator.plays = plays
            view.evaluateJavaScript("window.dabblePlay && window.dabblePlay()")
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
        window.onSpotifyIframeApiReady = function (api) {
          api.createController(document.getElementById('player'),
            { uri: 'spotify:track:\(trackID)', width: '100%', height: \(Int(height)) },
            function (controller) {
              window.dabblePlay = function () { controller.play(); };
              \(autoplay ? "controller.addListener('ready', window.dabblePlay);" : "")
            });
        };
        </script>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var trackID: String?
        var plays = 0
        var swipedLeft: () -> Void = {}

        @objc func swiped() { swipedLeft() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        /// Links in the player (the Spotify logo, the song's page) open outside the app.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated || action.targetFrame == nil, let url = action.request.url else { return .allow }
            await UIApplication.shared.open(url)
            return .cancel
        }
    }
}
