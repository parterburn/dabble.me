import SafariServices
import SwiftUI
import UIKit

/// dabble.me pages (help, privacy, account security…) open in a Safari sheet inside the app rather
/// than leaving for the browser. Other sites' links, and the link to subscribe (which App Store
/// rules want opened in the browser), go out as before. The sheet keeps its own website data,
/// apart from Safari's, and signing out of the app clears it.
@MainActor
enum WebLinks {
    static func opensInApp(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host()?.lowercased() else { return false }
        let ours = [AppConfig.baseURL.host(), AppConfig.productionURL.host()].compactMap { $0?.lowercased() }
        guard ours.contains(host) else { return false }
        return !url.path.hasPrefix("/subscribe")
    }

    /// For `OpenURLAction`: shows the page in the app when it's one of ours.
    static func open(_ url: URL) -> OpenURLAction.Result {
        guard opensInApp(url) else { return .systemAction }
        present(url)
        return .handled
    }

    private static func present(_ url: URL) {
        guard var top = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController
        else { return }
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = UIColor(named: "AccentColor")
        safari.dismissButtonStyle = .close
        top.present(safari, animated: true)
    }

    /// Signing out of the app signs the in-app pages out too.
    static func clearWebsiteData() async {
        await SFSafariViewController.DataStore.default.clearWebsiteData()
    }
}

extension View {
    /// Links to dabble.me open in the app (see `WebLinks`).
    func opensDabbleLinksInApp() -> some View {
        environment(\.openURL, OpenURLAction { WebLinks.open($0) })
    }
}
