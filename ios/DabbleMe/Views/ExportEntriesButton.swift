import SwiftUI

/// Export Entries, without the web: asks the server for the same export of the whole journal
/// the web's Export page makes (`POST /api/v1/exports`), and the server emails the link, as it
/// does for the web. The alert says which address it goes to. The emailed link opens
/// dabble.me, which asks for a sign-in before the download.
struct ExportEntriesButton<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder let label: () -> Content

    @State private var isWorking = false
    @State private var outcome: Outcome?

    private struct Outcome {
        let title: String
        let message: String
    }

    var body: some View {
        Button(action: export) {
            HStack {
                label()
                if isWorking {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isWorking)
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

    private func export() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let result = try await model.requestExport()
                outcome = Outcome(title: result.title, message: result.message)
            } catch is CancellationError {
            } catch {
                outcome = Outcome(title: "Couldn't Start the Export", message: error.localizedDescription)
            }
        }
    }
}
