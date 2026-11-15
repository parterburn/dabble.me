import SwiftUI
import UIKit

extension Notification.Name {
    static let deviceDidShake = Notification.Name("DabbleMeDeviceDidShake")
}

/// Settings → Shake for Random Entry: on unless it's been switched off.
enum ShakeSetting {
    static let storageKey = "shake.randomEntry"
    static var isOn: Bool { UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true }
}

extension UIWindow {
    /// Shake the phone for a random memory (unless that's switched off in Settings). Not while
    /// typing: there, shaking is iOS's Undo.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake, ShakeSetting.isOn, !Self.isTyping(in: self) else { return }
        NotificationCenter.default.post(name: .deviceDidShake, object: nil)
    }

    /// Something is up over the app: a sheet (a reflection, the composer, an entry's actions) or the
    /// full-screen photo. A shake leaves it alone rather than putting a random memory in its place.
    @MainActor
    static var isShowingSomethingOverApp: Bool {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?
            .rootViewController?.presentedViewController != nil
    }

    private static func isTyping(in view: UIView) -> Bool {
        if view.isFirstResponder, view is UITextView || view is UITextField { return true }
        return view.subviews.contains { isTyping(in: $0) }
    }
}

/// A random entry as a preview, over whatever you were reading: an accidental shake never
/// replaces it. The round button beside the X opens the entry in Journal, and Another (or
/// another shake) picks again.
struct RandomEntrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var entry: EntryDetail?
    @State private var error: String?
    @State private var isLoading = false
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "A Random Memory", icon: "slab-dice") { openButton }
            Group {
                if let entry {
                    preview(entry)
                        .id(entry.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                } else if let error {
                    ContentUnavailableView {
                        Label("No memory to show", icon: "slab-dice")
                    } description: {
                        Text(error)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            // Another (as a shake gives), centered, floating over the entry's end.
            .overlay(alignment: .bottom) { bar }
        }
        .padding([.horizontal, .top], 20)
        // Another sits at the sheet's foot, as far from its bottom edge as from its sides
        // (the home indicator's safe area on top of the padding left a gap under it).
        .padding(.bottom, 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .bottom)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            Task { await load() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: entry?.id)
    }

    /// The whole entry, scrollable inside the sheet (drag the sheet up for more room). Its links
    /// work: a #tag searches, an address opens.
    private func preview(_ entry: EntryDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.dateLine(for: entry.day, fallback: entry.date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                if let document = entry.document {
                    DocumentText(blocks: RichText.droppingTrailing(hashtags: (entry.datedHashtags ?? []).map(\.tag), songLinks: !entry.songs.isEmpty, from: document), font: .system(size: bodySize * textSize.scale, design: fontStyle.design), scale: textSize.scale, bodySize: bodySize)
                } else {
                    Text(RichText.linkingURLs(in: RichText.linkingHashtags(in: AttributedString.journal(RichText.droppingTrailing(hashtags: (entry.datedHashtags ?? []).map(\.tag), songLinks: !entry.songs.isEmpty, from: entry.bodyText)))))
                        .font(.system(size: bodySize * textSize.scale, design: fontStyle.design))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !entry.songs.isEmpty {
                    SongList(songs: entry.songs)
                }
                // Dated #tags with their age, above the photo, as in the timeline.
                if let dated = entry.datedHashtags, !dated.isEmpty {
                    DatedHashtagRow(hashtags: dated)
                }
                if entry.imageProcessing || entry.imageURL != nil {
                    EntryPhoto(url: entry.imageURL, isProcessing: entry.imageProcessing, day: entry.day)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Self.barClearance) // the entry's end scrolls clear of the bar over it
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: .infinity, alignment: .top)
        // Links work here too: a #tag closes this and searches for it; a web page opens (dabble.me's
        // in the app).
        .environment(\.openURL, OpenURLAction { url in
            if let tag = RichText.hashtag(from: url) {
                dismiss()
                model.search(hashtag: tag)
                return .handled
            }
            return WebLinks.open(url)
        })
    }

    /// Room to leave under an entry that scrolls beneath the bar.
    private static let barClearance: CGFloat = 76

    /// Opens the entry in full, in the Journal: a round button like the X beside it.
    private var openButton: some View {
        Button {
            guard let entry else { return }
            model.selectedTab = .journal
            model.openEntryRequest = entry.id
            dismiss()
        } label: {
            appIcon("slab-expand")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .modifier(RoundButtonBacking(overPhoto: false))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(entry == nil)
        .accessibilityLabel("Open")
        .accessibilityHint("Opens this entry in the Journal")
    }

    /// The sheet's foot: another random memory.
    private var bar: some View {
        Button { Task { await load() } } label: {
            Label("Another", icon: "slab-arrows-rotate").frame(width: 150, height: 26)
        }
        // While another loads it waits without dimming (it would blink with every tap).
        .allowsHitTesting(!isLoading)
        .accessibilityHint("Shows another random memory")
        .filledButtonStyle()
        // Medium weight, like the app's other main buttons, a size down from them.
        .fontWeight(.medium)
        .controlSize(.regular)
        .buttonBorderShape(.capsule)
        // No panel behind it: it floats over the entry, lifted a little off its words.
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await model.randomEntry()
            withAnimation(.snappy) { entry = next }
            error = nil
        } catch is CancellationError {
        } catch {
            if entry == nil { self.error = error.localizedDescription }
        }
    }
}
