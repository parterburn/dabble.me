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
/// replaces it. Open goes to the entry in Journal, the arrows beside it to the entry before or
/// after, and the dice at the top left (or another shake) picks again.
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
            // The dice rolls again (as another shake does).
            SheetHeader(title: "A Random Memory") {
                SheetIconButton(icon: "slab-dice", label: "Another") { Task { await load() } }
                    .disabled(isLoading)
                    .accessibilityHint("Shows another random memory")
            }
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
            // Open, between the entries before and after this one.
            EntryStepBar(entry: entry, isLoading: isLoading) { id in
                Task { await load(id) }
            } open: {
                guard let entry else { return }
                model.selectedTab = .journal
                model.openEntryRequest = entry.id
                dismiss()
            }
        }
        .padding([.horizontal, .top], 20)
        // The Open bar sits at the sheet's foot, as far from its bottom edge as from its sides
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

    /// The whole entry, scrollable inside the sheet (drag the sheet up for more room). Links in it
    /// don't navigate from here; Open goes to the entry.
    private func preview(_ entry: EntryDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.dateLine(for: entry.day, fallback: entry.date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                if let document = entry.document {
                    DocumentText(blocks: RichText.droppingTrailing(hashtags: (entry.datedHashtags ?? []).map(\.tag), songLinks: !entry.songs.isEmpty, from: document), font: .system(size: bodySize * textSize.scale, design: fontStyle.design), scale: textSize.scale, bodySize: bodySize)
                } else {
                    Text(AttributedString.journal(RichText.droppingTrailing(hashtags: (entry.datedHashtags ?? []).map(\.tag), songLinks: !entry.songs.isEmpty, from: entry.bodyText)))
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
            .padding(.bottom, 8)
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(\.openURL, OpenURLAction { _ in .discarded })
    }

    /// A random entry, or (stepping to the one before or after) the entry with `id`.
    private func load(_ id: Int? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = if let id { try await model.entry(id: id) } else { try await model.randomEntry() }
            withAnimation(.snappy) { entry = next }
            error = nil
        } catch is CancellationError {
        } catch {
            if entry == nil { self.error = error.localizedDescription }
        }
    }
}

/// The bottom of an entry's sheet: Open, with an arrow each side for the entry before it and the
/// one after (greyed out at either end of the journal).
struct EntryStepBar: View {
    let entry: EntryDetail?
    var isLoading = false
    /// Shows the entry with this id in the sheet.
    let step: (Int) -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            arrow("slab-angle-left", "Previous Entry", to: entry?.previousEntry)
            Button(action: open) {
                Label("Open", icon: "slab-expand").frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.borderedProminent)
            .disabled(entry == nil)
            arrow("slab-angle-right", "Next Entry", to: entry?.nextEntry)
        }
        // Medium weight, like the app's other main buttons, a size down from them.
        .fontWeight(.medium)
        .controlSize(.regular)
        .buttonBorderShape(.capsule)
    }

    private func arrow(_ icon: String, _ label: String, to neighbour: EntryNeighbour?) -> some View {
        Button {
            if let neighbour { step(neighbour.id) }
        } label: {
            appIcon(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .frame(width: 24, height: 26)
        }
        .buttonStyle(.bordered)
        .disabled(neighbour == nil || isLoading)
        .accessibilityLabel(label)
        .accessibilityValue(neighbour?.day?.long ?? "")
    }
}
