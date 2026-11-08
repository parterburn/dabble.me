#if DEBUG
import SwiftUI

/// Debug builds only: choose which Dabble Me server to sign in to. Use your Mac's
/// address (e.g. http://pauls-macbook.local:3000) to reach a local server from a phone.
struct ServerPicker: View {
    @State private var current = AppConfig.baseURL.absoluteString
    @State private var custom = ""
    @State private var editingCustom = false

    var body: some View {
        Menu {
            Button("Local (\(AppConfig.defaultBaseURL.host() ?? "localhost"))") { select(nil) }
            Button("Production (dabble.me)") { select(AppConfig.productionURL) }
            Button("Other…") {
                custom = current
                editingCustom = true
            }
        } label: {
            Label("Server: \(current)", systemImage: "server.rack")
                .font(.footnote)
        }
        .alert("Server URL", isPresented: $editingCustom) {
            TextField("http://my-mac.local:3000", text: $custom)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Use") {
                if let url = URL(string: custom.trimmingCharacters(in: .whitespaces)), url.scheme != nil {
                    select(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func select(_ url: URL?) {
        AppConfig.setServerOverride(url)
        current = AppConfig.baseURL.absoluteString
    }
}
#endif
