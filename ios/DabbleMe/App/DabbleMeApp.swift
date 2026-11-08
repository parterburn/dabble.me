import SwiftUI

@main
struct DabbleMeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.isSignedIn {
                MainTabs()
            } else {
                SignInView()
            }
        }
        .task(id: model.isSignedIn) {
            if model.isSignedIn, !model.hasLoaded { await model.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up entries that arrived by email while the app was in the background.
            if phase == .active, model.isSignedIn, model.hasLoaded {
                Task { await model.refresh() }
            }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            Tab("Journal", systemImage: "book.closed") {
                JournalView()
            }
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
