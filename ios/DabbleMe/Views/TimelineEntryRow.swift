import SwiftUI

/// A timeline/search/On This Day row, laid out like a post in a feed: the date in its own column
/// on the left, a long preview, then the photo large below it. A preview that's cut off says
/// "Show more" and a tap anywhere expands it in place; otherwise (or once expanded) a tap opens the
/// entry. While you read a long expanded entry, its date floats down alongside it. Swipe left for
/// Actions (Reflect, Edit, Delete and the entry's tags).
struct TimelineEntryRow: View {
    let entry: EntrySummary
    var showsYear = false
    let isExpanded: Bool
    let actions: EntryActions
    let onExpand: () -> Void
    let onOpen: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.timelinePinTop) private var pinTop
    @State private var full: EntryDetail?
    @State private var previewHeight: CGFloat = 0
    @State private var fullPreviewHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif

    /// Lines of preview before "Show more".
    private static let previewLines = 7
    private static let avatarColumn: CGFloat = 42
    private static let gutter: CGFloat = 14

    private var bodyFont: Font { .system(size: bodySize * textSize.scale, design: fontStyle.design) }
    private var previewText: String { entry.previewText ?? entry.excerpt }

    /// Collapsed and expanded are the same text, set the same way: expanding only lifts the line
    /// limit (and swaps in the full text when the server's preview was cut short), so nothing
    /// shifts. Light Markdown; list lines ("- item") show as bullets. #hashtags are tinted, and
    /// links once expanded (collapsed, a tap anywhere expands).
    private var styledText: AttributedString {
        let source = isExpanded ? (full?.bodyText ?? previewText) : previewText
        if source.isEmpty { return AttributedString("📷 Photo") }
        let text = AttributedString.journal(Self.bullets(source))
        return isExpanded ? RichText.linkingURLs(in: RichText.linkingHashtags(in: text)) : Self.tintingHashtags(in: text)
    }

    private static func bullets(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                for marker in ["- ", "* "] where line.hasPrefix(marker) { return "• " + line.dropFirst(2) }
                return String(line)
            }
            .joined(separator: "\n")
    }

    private static func tintingHashtags(in text: AttributedString) -> AttributedString {
        var result = text
        let string = String(result.characters)
        let regex = try! NSRegularExpression(pattern: "(?<![\\w&/#])#([0-9]*[A-Za-z_][A-Za-z0-9_]*)")
        for match in regex.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
            guard let range = Range(match.range, in: result) else { continue }
            result[range].foregroundColor = Color("AccentColor")
        }
        return result
    }

    /// The server's preview stops at about 1,500 characters; past that, expanding loads the rest.
    private var previewIsCut: Bool {
        // The server says; an older one didn't, but its cut previews end in "...".
        entry.previewTruncated ?? (entry.previewText?.hasSuffix("...") ?? false)
    }

    /// More to read than the preview shows: cut off on screen, or longer than the server's preview.
    private var isTruncated: Bool {
        fullPreviewHeight > previewHeight + 1 || previewIsCut
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsYear, let year = entry.day?.year {
                // Search and On This Day: "1 year ago · 2025".
                Text(entry.yearsAgo.map { "\($0 == 1 ? "1 year" : "\($0) years") ago · \(year)" } ?? year)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            entryText
            // Songs once the whole entry shows (expanded, or short enough not to need it).
            if let songs = entry.songs, !songs.isEmpty, isExpanded || !isTruncated {
                SongList(songs: songs)
            }
            // Only dated #tags get a line of their own (their age), just above the photo.
            if let dated = entry.datedHashtags, !dated.isEmpty {
                DatedHashtagRow(hashtags: dated)
            }
            if entry.imageProcessing || entry.imageURL != nil {
                EntryPhoto(url: entry.thumbnailURL(width: 1000), isProcessing: entry.imageProcessing)
                    .frame(maxWidth: .infinity, maxHeight: 320, alignment: .leading)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        // At least as tall as the date beside it, so a one-line entry doesn't crowd the divider.
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .padding(.leading, Self.avatarColumn + Self.gutter)
        .overlay(alignment: .topLeading) { floatingDate }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .onTapGesture {
            if !isExpanded, isTruncated { onExpand() } else { onOpen() }
        }
        // Reload the full entry whenever its summary changes (an edit, or a refresh that brought
        // new text from the web or email), not just the first time it's expanded.
        // Only when the server's preview was cut short: otherwise the preview is the whole entry.
        .task(id: "\(isExpanded)|\(entry.updatedAt)") {
            guard isExpanded, previewIsCut else { return }
            if full?.updatedAt != entry.updatedAt { full = try? await model.entry(id: entry.id) }
        }
        // Swipe left for Actions (a tap opens).
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Task { await actions.showActions(for: entry.id, model: model) }
            } label: {
                Label("Actions", icon: "slab-bolt")
            }
            .tint(.gray)
        }
        // Collapsed it reads as one; expanded, its #tag pills are buttons of their own.
        .accessibilityElement(children: isExpanded ? .contain : .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(!isExpanded && isTruncated ? "Shows the whole entry" : "Opens the entry")
    }

    /// One `Text` either way, with "Show more" when there's more. The full height is measured
    /// behind it to tell.
    private var entryText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(styledText)
                .font(bodyFont)
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : Self.previewLines)
                // Expanded, its full height (a list row would otherwise keep the collapsed height).
                .fixedSize(horizontal: false, vertical: isExpanded)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { previewHeight = $0 }
                .background(alignment: .topLeading) {
                    if !isExpanded {
                        Text(styledText)
                            .font(bodyFont)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullPreviewHeight = $0 }
                    }
                }
            if !isExpanded, isTruncated {
                Text("Show more")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
    }

    /// "THU / 7" in the left column. In a row taller than the screen it stays just below the
    /// sticky month header while the row scrolls by, then leaves with it.
    private var floatingDate: some View {
        let pin = pinTop
        let height: CGFloat = 52
        return VStack(spacing: 0) {
            Text(entry.day?.weekdayShort.uppercased() ?? "")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.day?.dayNumber ?? "")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(width: Self.avatarColumn, height: height, alignment: .top)
        .padding(.top, 2)
        .frame(maxHeight: .infinity, alignment: .top)
        .visualEffect { content, proxy in
            let frame = proxy.frame(in: .scrollView)
            let travel = max(frame.height - height - 8, 0)
            return content.offset(y: min(max(pin - frame.minY, 0), travel))
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// A timeline row in a list: close to the screen edges, with separators running edge to edge.
    func timelineRowLayout() -> some View {
        let side: CGFloat = 12
        return listRowInsets(EdgeInsets(top: 8, leading: side, bottom: 8, trailing: side))
            .alignmentGuide(.listRowSeparatorLeading) { _ in -side }
            .alignmentGuide(.listRowSeparatorTrailing) { $0.width + side }
    }
}

extension EnvironmentValues {
    /// Where a long expanded row's date stops as it scrolls up: the bottom of the list's sticky
    /// header, in the scroll view's coordinates.
    @Entry var timelinePinTop: CGFloat = 0
}

extension View {
    /// Lets the rows in this list float their dates just under its sticky section headers.
    func timelinePinsDates(headerHeight: CGFloat = 34) -> some View {
        modifier(TimelinePinsDates(headerHeight: headerHeight))
    }
}

private struct TimelinePinsDates: ViewModifier {
    let headerHeight: CGFloat
    @State private var top: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, inset in top = inset }
            .environment(\.timelinePinTop, top + headerHeight)
    }
}

/// Reflect/Edit from a row's swipe actions: loads the entry, then shows the reflection or the editor.
@MainActor
@Observable
final class EntryActions {
    var editing: EntryDetail?
    var reflection: EntryReflection?
    /// The Actions sheet (swipe left → Actions), and an entry waiting on "Delete?".
    var sheet: EntryDetail?
    var deleting: EntryDetail?
    var isWorking = false
    var error: String?

    func showActions(for id: Int, model: AppModel) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            sheet = try await model.entry(id: id)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Edits in the app when it can represent the entry's formatting; otherwise on dabble.me.
    func edit(_ id: Int, model: AppModel) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let entry = try await model.entry(id: id)
            if entry.document != nil { editing = entry } else { await UIApplication.shared.open(entry.webUrl) }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ entry: EntryDetail, model: AppModel) async {
        do {
            try await model.deleteEntry(id: entry.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reflect(on id: Int, model: AppModel) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            reflection = try await model.reflection(on: try await model.entry(id: id))
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension View {
    func entryActionSheets(_ actions: EntryActions) -> some View {
        modifier(EntryActionSheets(actions: actions))
    }
}

private struct EntryActionSheets: ViewModifier {
    @Bindable var actions: EntryActions
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.editing) { entry in
                ComposeView(mode: .edit(entry))
            }
            .sheet(item: $actions.reflection) { reflection in
                ReflectionSheet(reflection: reflection)
            }
            .sheet(item: $actions.sheet) { entry in
                EntryActionsSheet(entry: entry, canReflect: JournalIntelligence.isEnabled(for: model.me) && !entry.bodyText.isEmpty,
                                  canEdit: model.me?.canEdit == true,
                                  canDelete: model.me?.mayDelete == true) { action in
                    actions.sheet = nil
                    switch action {
                    case .reflect: Task { await actions.reflect(on: entry.id, model: model) }
                    case .edit: if entry.document != nil { actions.editing = entry } else { openURL(entry.webUrl) }
                    case .delete: actions.deleting = entry
                    case .web: openURL(entry.webUrl)
                    case .search(let tag): if let url = URL(string: "\(RichText.hashtagScheme):\(tag)") { openURL(url) }
                    }
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: Binding(get: { actions.deleting != nil }, set: { if !$0 { actions.deleting = nil } }),
                                titleVisibility: .visible, presenting: actions.deleting) { entry in
                Button("Delete Entry", role: .destructive) { Task { await actions.delete(entry, model: model) } }
            } message: { _ in
                Text("This can't be undone.")
            }
            .overlay {
                if actions.isWorking {
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
            }
            .alert("Something went wrong", isPresented: .present($actions.error)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actions.error ?? "")
            }
    }
}

/// An entry's Spotify songs, each a link to it: on the entry, in previews and expanded rows.
struct SongList: View {
    let songs: [Song]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(songs, id: \.self) { song in
                Link(destination: song.spotifyUrl) {
                    Label(song.label, icon: "slab-music")
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .font(.subheadline)
    }
}
