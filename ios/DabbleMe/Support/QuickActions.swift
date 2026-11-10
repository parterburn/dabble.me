import SwiftUI
import UIKit

/// Home Screen quick actions (touch and hold the app icon): New Entry, View Journal, Search
/// Journal. Declared in Info.plist (project.yml); this routes them once the app is signed in.
enum QuickAction: String {
    case newEntry = "me.dabble.ios.new-entry"
    case journal = "me.dabble.ios.journal"
    case search = "me.dabble.ios.search"

    @MainActor
    func perform(in model: AppModel) {
        switch self {
        case .newEntry:
            model.selectedTab = .today
            model.composeRequest = true
        case .journal:
            model.selectedTab = .journal
        case .search:
            model.selectedTab = .search
            model.searchFocusRequest += 1
        }
    }
}

/// Holds a quick action until the app can act on it: one that launched the app arrives before
/// it has signed in and loaded.
@MainActor
final class QuickActionRouter {
    static let shared = QuickActionRouter()
    weak var model: AppModel?
    private var pending: QuickAction?

    func handle(_ item: UIApplicationShortcutItem) {
        guard let action = QuickAction(rawValue: item.type) else { return }
        pending = action
        performPending()
    }

    /// Called again once the app has signed in and loaded.
    func performPending() {
        guard let action = pending, let model, model.isSignedIn, model.hasLoaded else { return }
        pending = nil
        action.perform(in: model)
    }
}

/// SwiftUI apps get quick actions through a scene delegate: one that launched the app comes with
/// the scene's connection options, later ones through `windowScene(_:performActionFor:)`.
final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { QuickActionRouter.shared.handle(item) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        guard QuickAction(rawValue: shortcutItem.type) != nil else { return false }
        QuickActionRouter.shared.handle(shortcutItem)
        return true
    }
}
