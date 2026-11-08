import SwiftUI

struct EntryDetailView: View {
    let entryID: Int

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var entry: EntryDetail?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    EntryBody(entry: entry)
                        .padding()
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
                .refreshable { await load() }
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
            Section("Text Size") {
                Button("Larger Text", systemImage: "textformat.size.larger") {
                    if let larger = textSize.larger { textSize = larger }
                }
                .disabled(textSize.larger == nil)
                Button("Smaller Text", systemImage: "textformat.size.smaller") {
                    if let smaller = textSize.smaller { textSize = smaller }
                }
                .disabled(textSize.smaller == nil)
            }
            if model.me?.canWrite == true {
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

    private func load() async {
        do {
            entry = try await model.entry(id: entryID)
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
            try await model.deleteEntry(id: entryID)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
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
