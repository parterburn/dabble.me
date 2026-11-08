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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            Task { await load() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: entry?.id)
    }

    private func preview(_ entry: EntryDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.day.map { "\($0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())) · \($0.relative(to: model.today?.day ?? JournalDay(localDate: .now)))" } ?? entry.date)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            Group {
                if let document = entry.document {
                    DocumentText(blocks: document, font: .system(size: bodySize, design: .serif), scale: 1, bodySize: bodySize)
                } else {
                    Text(AttributedString.journal(entry.bodyText))
                        .font(.system(size: bodySize, design: .serif))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: entry.imageURL == nil ? 260 : 150, alignment: .top)
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            if entry.imageURL != nil, !entry.imageProcessing {
                AsyncImage(url: entry.summary.thumbnailURL(width: 700)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
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
