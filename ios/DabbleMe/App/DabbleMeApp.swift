import SwiftUI

@main
struct DabbleMeApp: App {
    @State private var model: AppModel

    init() {
        #if DEBUG
        // Automation (UI tests, screenshots) can skip the web sign-in sheet:
        //   -DabbleDebugAccessToken <token from `rails ios:demo_account`>
        if let token = UserDefaults.standard.string(forKey: "DabbleDebugAccessToken"), !token.isEmpty {
            KeychainStore.save(OAuthTokens(accessToken: token, refreshToken: nil, expiresAt: nil))
        }
        #endif
        _model = State(initialValue: AppModel())
    }

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
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // No `.search` role: it pins Search to the far right, and Settings belongs there.
        TabView(selection: $model.selectedTab) {
            Tab("Journal", systemImage: "book.closed", value: AppModel.Tab.journal) {
                JournalView()
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppModel.Tab.search) {
                SearchView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppModel.Tab.settings) {
                SettingsView()
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let tag = RichText.hashtag(from: url) {
                model.search(hashtag: tag)
                return .handled
            }
            return .systemAction
        })
    }
}
