import BackgroundTasks
import SwiftUI
import UserNotifications

@main
struct DabbleMeApp: App {
    @UIApplicationDelegateAdaptor(QuickActionAppDelegate.self) private var appDelegate
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
        QuickActionRouter.shared.model = model
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        // Now and then while the app's closed: the daily reminders are built again, so an entry
        // written since (by email, say) can be the one a later day looks back on.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await model.refreshRemindersInBackground()
        }
    }
}

/// iOS decides when (and whether) this runs; it's asked for again each time the app goes into the
/// background and each time it has run.
enum BackgroundRefresh {
    static let identifier = "me.dabble.ios.reminders"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.system
    /// The typing animation, once per launch, when signed in (the welcome screen has its own).
    @State private var showsSplash = true

    var body: some View {
        Group {
            #if DEBUG
            // UI tests: -DabbleDebugPhotoURL <url> shows a single entry photo (viewer + menu checks).
            if let raw = UserDefaults.standard.string(forKey: "DabbleDebugPhotoURL"), let url = URL(string: raw) {
                // From three years ago, so sharing it makes a "3 years ago" card.
                let day = Calendar.current.date(byAdding: .year, value: -3, to: .now).map { JournalDay(localDate: $0) }
                ScrollView { EntryPhoto(url: url, isProcessing: false, day: day).padding() }
            } else {
                content
            }
            #else
            content
            #endif
        }
        .preferredColorScheme(theme.colorScheme)
        .onOpenURL { url in
            // From the widget: me.dabble.app:/write, :/today, :/today/edit ("Add to today"), or
            // :/entry/<id> (the entry it shows).
            // (Sign-in callbacks never get here; the web sign-in session handles them.)
            guard model.isSignedIn, url.scheme == "me.dabble.app" else { return }
            #if DEBUG
            // UI tests can't shake the simulator: me.dabble.app:/shake does the same.
            if url.path == "/shake" {
                if ShakeSetting.isOn { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
                return
            }
            #endif
            if url.path.hasPrefix("/entry/"), let id = Int(url.lastPathComponent) {
                model.selectedTab = .journal
                model.openEntryRequest = id
                return
            }
            model.selectedTab = .today
            if url.path == "/write" { model.composeRequest = true }
            if url.path == "/today/edit" { model.editTodayRequest = true }
        }
        .task(id: model.isSignedIn) {
            if model.isSignedIn, !model.hasLoaded { await model.refresh() }
        }
        // A Home Screen quick action that launched the app waits until it has loaded.
        .onChange(of: model.hasLoaded, initial: true) { _, loaded in
            if loaded { QuickActionRouter.shared.performPending() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                model.lock.didEnterBackground()
                if model.isSignedIn { BackgroundRefresh.schedule() }
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
        .overlay {
            // With the lock on, the lock screen types the wordmark instead.
            if showsSplash, model.isSignedIn, !model.lock.isEnabled {
                SplashView(isReady: model.hasLoaded) {
                    withAnimation(.easeOut(duration: 0.35)) { showsSplash = false }
                }
                .transition(.opacity)
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
            Tab("Today", image: tabIcon("slab-calendar", .today), value: AppModel.Tab.today) {
                TodayView().tabBarClearance()
            }
            Tab("Journal", image: tabIcon("slab-book", .journal), value: AppModel.Tab.journal) {
                JournalView().tabBarClearance()
            }
            Tab("Search", image: tabIcon("slab-search", .search), value: AppModel.Tab.search) {
                SearchView().tabBarClearance()
            }
            Tab("Settings", image: tabIcon("slab-gear", .settings), value: AppModel.Tab.settings) {
                SettingsView().tabBarClearance()
            }
        }
        .sheet(isPresented: $model.showsRandomEntry) { RandomEntrySheet() }
        // One sheet at a time: the day sheet's calendar button closes it, then opens the calendar;
        // a day picked there closes the calendar, then opens its sheet.
        .sheet(item: $model.statsDay, onDismiss: {
            guard model.reopensDayPicker else { return }
            model.reopensDayPicker = false
            model.showsDayPicker = true
        }) { DayEntriesSheet(day: $0.day) }
        .sheet(isPresented: $model.showsDayPicker, onDismiss: {
            guard let day = model.pickedDay else { return }
            model.pickedDay = nil
            model.dayPickerOpensOn = day
            model.statsDay = StatsDay(day: day)
        }) { DayPickerSheet { model.pickedDay = $0 } }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            // The open sheet picks another itself; otherwise show one. Not while locked, and not
            // over anything else that's up (a reflection, writing or editing, any sheet).
            guard !model.showsRandomEntry, !model.lock.isLocked, !UIWindow.isShowingSomethingOverApp else { return }
            Task {
                // Right after launch the journal may still be loading.
                for _ in 0..<20 where !model.hasLoaded { try? await Task.sleep(for: .milliseconds(250)) }
                guard model.hasLoaded, !model.months.isEmpty else { return }
                model.showsRandomEntry = true
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let tag = RichText.hashtag(from: url) {
                model.search(hashtag: tag)
                return .handled
            }
            return WebLinks.open(url)
        })
    }

    /// The selected tab shows the filled version of its icon.
    private func tabIcon(_ name: String, _ tab: AppModel.Tab) -> String {
        model.selectedTab == tab ? name + "-full" : name
    }
}

extension View {
    /// Room at the bottom of a tab's scrolling content, so its last lines clear the floating tab bar.
    func tabBarClearance() -> some View {
        contentMargins(.bottom, 24, for: .scrollContent)
    }
}
