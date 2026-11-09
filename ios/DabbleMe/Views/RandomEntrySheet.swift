import SwiftUI
import UIKit

extension Notification.Name {
    static let deviceDidShake = Notification.Name("DabbleMeDeviceDidShake")
}

extension UIWindow {
    /// Shake the phone for a random memory. Not while typing: there, shaking is iOS's Undo.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake, !Self.isTyping(in: self) else { return }
        NotificationCenter.default.post(name: .deviceDidShake, object: nil)
    }

    private static func isTyping(in view: UIView) -> Bool {
        if view.isFirstResponder, view is UITextView || view is UITextField { return true }
        return view.subviews.contains { isTyping(in: $0) }
    }
}

/// A random entry as a preview, over whatever you were reading: an accidental shake never
/// replaces it. Open goes to the entry in Journal; Another (or another shake) picks again.
struct RandomEntrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var entry: EntryDetail?
    @State private var error: String?
    @State private var isLoading = false
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("A Random Memory", systemImage: "dice")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: { Label("Close", icon: "slab-close") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
            }
            if let entry {
                preview(entry)
                    .id(entry.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else if let error {
                ContentUnavailableView("No memory to show", systemImage: "dice", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
            HStack(spacing: 12) {
                Button {
                    Task { await load() }
                } label: {
                    Label("Another", icon: "slab-arrows-rotate").frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                Button {
                    guard let entry else { return }
                    model.selectedTab = .journal
                    model.openEntryRequest = entry.id
                    dismiss()
                } label: {
                    Label("Open", icon: "slab-expand").frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .disabled(entry == nil)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
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
                Text(entry.day.map { "\($0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())) · \($0.relative(to: model.today?.day ?? JournalDay(localDate: .now)))" } ?? entry.date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                if let document = entry.document {
                    DocumentText(blocks: document, font: .system(size: bodySize * textSize.scale, design: .serif), scale: textSize.scale, bodySize: bodySize)
                } else {
                    Text(AttributedString.journal(entry.bodyText))
                        .font(.system(size: bodySize * textSize.scale, design: .serif))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if entry.imageProcessing || entry.imageURL != nil {
                    EntryPhoto(url: entry.imageURL, isProcessing: entry.imageProcessing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(\.openURL, OpenURLAction { _ in .discarded })
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
