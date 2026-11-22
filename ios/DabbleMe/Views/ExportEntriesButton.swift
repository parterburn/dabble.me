import SwiftUI

/// Export Entries, without the web: asks the server for the same export of the whole journal
/// the web's Export page makes (`POST /api/v1/exports`), and the server emails the link, as it
/// does for the web. The alert says which address it goes to. The emailed link opens
/// dabble.me, which asks for a sign-in before the download. A Cancel/Export alert comes first,
/// so one stray tap doesn't send the whole journal out.
struct ExportEntriesButton<Content: View>: View {
    @Environment(AppModel.self) private var model
    /// On the Delete Account page: the alert says to download it before deleting.
    var beforeDeleting = false
    @ViewBuilder let label: () -> Content

    @State private var isWorking = false
    @State private var isConfirming = false
    @State private var outcome: Outcome?

    private struct Outcome {
        let title: String
        let message: String
    }

    var body: some View {
        Button { isConfirming = true } label: {
            HStack {
                label()
                if isWorking {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isWorking)
        .alert("Export Entries?", isPresented: $isConfirming) {
            Button("Cancel", role: .cancel) {}
            Button("Export", action: export)
        } message: {
            Text(confirmMessage)
        }
        .alert(
            outcome?.title ?? "",
            isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } }),
            presenting: outcome
        ) { _ in
            Button("OK") {}
        } message: { outcome in
            Text(outcome.message)
        }
    }

    private var confirmMessage: String {
        "We'll email \(model.me?.email ?? "you") a link to a ZIP of all your entries."
    }

    private func export() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let result = try await model.requestExport()
                outcome = Outcome(title: result.title, message: result.message(beforeDeleting: beforeDeleting))
            } catch is CancellationError {
            } catch {
                outcome = Outcome(title: "Couldn't Start the Export", message: error.localizedDescription)
            }
        }
    }
}
