import SwiftUI
import UserNotifications

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
        // -DabbleDebugSignedOut YES starts signed out (the welcome screens).
        if UserDefaults.standard.bool(forKey: "DabbleDebugSignedOut") { KeychainStore.delete() }
        #endif
        let model = AppModel()
        _model = State(initialValue: model)
        NotificationRouter.shared.model = model
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
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
            #if DEBUG
            // UI tests: -DabbleDebugPhotoURL <url> shows a single entry photo (viewer + menu checks).
            if let raw = UserDefaults.standard.string(forKey: "DabbleDebugPhotoURL"), let url = URL(string: raw) {
                ScrollView { EntryPhoto(url: url, isProcessing: false).padding() }
            } else {
                content
            }
            #else
            content
            #endif
        }
        .onOpenURL { url in
            // From the widget: me.dabble.app:/write or :/today. (Sign-in callbacks never get here;
            // the web sign-in session handles them.)
            guard model.isSignedIn, url.scheme == "me.dabble.app" else { return }
            model.selectedTab = .today
            if url.path == "/write" { model.composeRequest = true }
        }
        .task(id: model.isSignedIn) {
            if model.isSignedIn, !model.hasLoaded { await model.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                model.lock.didEnterBackground()
            case .active:
                model.lock.willEnterForeground()
                // Pick up entries that arrived by email while the app was in the background.
                if model.isSignedIn, model.hasLoaded {
                    Task { await model.refresh() }
                }
            default:
                break
            }
        }
        .overlay {
            if model.isSignedIn, model.lock.isEnabled {
                if model.lock.isLocked {
                    LockScreen()
                } else if scenePhase != .active {
                    PrivacyCover() // hides the journal in the app switcher
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isSignedIn {
            MainTabs()
        } else {
            SignInView()
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // No `.search` role: it pins Search to the far right, and Settings belongs there.
        // Tapping the Search tab again focuses its search field.
        let selection = Binding<AppModel.Tab>(
            get: { model.selectedTab },
            set: { tab in
                if tab == .search, model.selectedTab == .search { model.searchFocusRequest += 1 }
                if tab == .journal, model.selectedTab == .journal { model.journalTopRequest += 1 }
                model.selectedTab = tab
            }
        )
        TabView(selection: selection) {
            Tab("Today", systemImage: "sun.max", value: AppModel.Tab.today) {
                TodayView()
            }
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
