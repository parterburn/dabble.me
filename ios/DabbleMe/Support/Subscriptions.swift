import Foundation
import Observation
import StoreKit
import SwiftUI

/// Dabble Me PRO bought in the app (StoreKit 2, auto-renewable, one subscription group).
///
/// Every purchase carries the account's `appleAccountToken`, so Apple's signed transaction names
/// the Dabble Me account it's for. The server is what turns a purchase into PRO: each verified
/// transaction is posted to `api/v1/apple_subscriptions`, which checks it with Apple, and only
/// then is the transaction finished. A transaction the server couldn't be told about stays
/// unfinished, so StoreKit hands it over again (`Transaction.unfinished`, at launch and sign-in).
@MainActor
@Observable
final class SubscriptionStore {
    nonisolated static let monthlyID = "me.dabble.ios.pro.monthly"
    nonisolated static let yearlyID = "me.dabble.ios.pro.yearly"
    nonisolated static let productIDs: Set<String> = [monthlyID, yearlyID]

    /// Yearly first.
    private(set) var products: [Product] = []
    private(set) var productsFailed = false
    /// "2 weeks free" for each plan with a free trial this Apple Account can still take. The
    /// trial and its length are set in App Store Connect (an introductory offer), not here.
    private(set) var freeTrials: [Product.ID: String] = [:]
    private(set) var isWorking = false
    /// What to tell the person: a purchase that's waiting for approval, a refusal, a failure.
    var message: String?
    /// This Apple Account already pays for PRO on a different Dabble Me account: the app offers
    /// no purchase then (a second purchase would only move it, see AppStore::Subscriptions).
    private(set) var belongsToOtherAccount = false

    @ObservationIgnored private let api: APIClient
    /// The signed-in account, to buy for; nil when signed out (nothing is sold or reported).
    @ObservationIgnored var accountToken: @MainActor () -> UUID? = { nil }
    /// After the server took a purchase: the account (and its plan) is loaded again.
    @ObservationIgnored var didChangePlan: @MainActor () async -> Void = {}
    @ObservationIgnored private var updates: Task<Void, Never>?
    /// A purchase here arrives twice: on `Transaction.updates` while StoreKit's "You're all set"
    /// is showing, and as the purchase's result once it's dismissed. Each is posted once: these
    /// are the transactions being posted now, and those the server answered this session.
    @ObservationIgnored private var reporting: Set<UInt64> = []
    @ObservationIgnored private var reported: Set<UInt64> = []

    init(api: APIClient) {
        self.api = api
    }

    /// Listens for transactions made outside a purchase here (renewals, Ask to Buy approvals,
    /// a purchase on another device, refunds), as early as the app starts, as StoreKit asks.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.report(result)
            }
        }
    }

    /// Signed out: nothing said to the last account carries over.
    func reset() {
        message = nil
        reported.removeAll()
        belongsToOtherAccount = false
    }

    /// Transactions StoreKit still has unfinished (the server couldn't be reached, or no one
    /// was signed in): reported now. Called after sign-in and whenever the account loads.
    func reportUnfinished() async {
        guard accountToken() != nil else { return }
        for await result in StoreKit.Transaction.unfinished {
            await report(result)
        }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let found = try await Product.products(for: Self.productIDs)
            products = found.sorted { ($0.id == Self.yearlyID ? 0 : 1) < ($1.id == Self.yearlyID ? 0 : 1) }
            productsFailed = products.isEmpty
            var trials: [Product.ID: String] = [:]
            for product in products {
                guard let subscription = product.subscription,
                      let offer = subscription.introductoryOffer, offer.paymentMode == .freeTrial,
                      await subscription.isEligibleForIntroOffer,
                      let length = offer.period.spelledOut else { continue }
                trials[product.id] = "\(length) free"
            }
            freeTrials = trials
        } catch {
            productsFailed = true
        }
    }

    /// Whether this Apple Account's current PRO subscription was bought for another account.
    func checkEntitlements() async {
        guard let mine = accountToken() else { return }
        var other = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let token = transaction.appAccountToken, token != mine {
                other = true
            }
        }
        belongsToOtherAccount = other
    }

    /// Buys with SwiftUI's `purchase` action (the view's `@Environment(\.purchase)`).
    func buy(_ product: Product, with purchase: PurchaseAction) async {
        guard let token = accountToken() else { return }
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        message = nil
        do {
            switch try await purchase(product, options: [.appAccountToken(token)]) {
            case .success(let result):
                await report(result)
            case .pending:
                message = "Your purchase is waiting for approval. PRO turns on as soon as it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The App Store couldn't complete the purchase. \(error.localizedDescription)"
        }
    }

    /// Restore Purchases: first what StoreKit already has on this device, which needs no
    /// sign-in. Only when that finds nothing does it sync with the App Store, which may ask for
    /// the Apple Account password. It always says how it went, except when that prompt is
    /// cancelled.
    func restore() async {
        guard accountToken() != nil, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        message = nil
        var outcome = await reportEntitlements()
        if outcome == .nothingFound {
            do {
                try await AppStore.sync()
            } catch StoreKitError.userCancelled {
                return
            } catch {
                message = "The App Store couldn't be reached to restore purchases. Try again in a moment."
                return
            }
            outcome = await reportEntitlements()
        }
        switch outcome {
        case .restored:
            message = "PRO restored."
        case .nothingFound:
            message = "No active Dabble Me PRO subscription was found for this Apple Account."
        case .explained:
            break // The server or the App Store already said why (another account, a failure).
        }
        await checkEntitlements()
    }

    private enum RestoreOutcome { case restored, nothingFound, explained }

    /// Posts every current PRO entitlement StoreKit has, as Restore Purchases does.
    private func reportEntitlements() async -> RestoreOutcome {
        var restored = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID) else { continue }
            if await report(result, again: true) == true { restored = true }
        }
        if restored { return .restored }
        return message == nil ? .nothingFound : .explained
    }

    /// Posts a verified transaction to the server, and finishes it once the server has it (or
    /// has refused it for good: another account's, Family Sharing). Unverified ones are left.
    /// `again`: Restore Purchases posts what the server already answered about, on purpose.
    /// Returns whether the server says the account is PRO now; nil when it wasn't asked or
    /// couldn't answer.
    @discardableResult
    private func report(_ result: VerificationResult<StoreKit.Transaction>, again: Bool = false) async -> Bool? {
        guard case .verified(let transaction) = result else {
            message = "The App Store couldn't verify that purchase."
            return nil
        }
        guard Self.productIDs.contains(transaction.productID) else {
            await transaction.finish() // Nothing else is sold; nothing to deliver.
            return nil
        }
        guard accountToken() != nil else { return nil } // Signed out: reported after sign-in.
        // A refund comes back with the same id (now with a revocation date): always posted.
        let repeatable = again || transaction.revocationDate != nil
        guard repeatable || !reported.contains(transaction.id), reporting.insert(transaction.id).inserted else { return nil }
        defer { reporting.remove(transaction.id) }
        do {
            let status: PlanStatus = try await api.post("api/v1/apple_subscriptions",
                                                        SignedTransaction(signedTransaction: result.jwsRepresentation))
            reported.insert(transaction.id)
            await transaction.finish()
            await didChangePlan()
            return status.isPro
        } catch let APIError.server(status, code, text) where status == 409 || status == 422 {
            reported.insert(transaction.id)
            await transaction.finish()
            if code == "subscription_belongs_to_other_account" { belongsToOtherAccount = true }
            message = text
            return false
        } catch is CancellationError {
            return nil
        } catch {
            message = "Your purchase went through, but Dabble Me couldn't be reached to turn on PRO. " +
                "It will finish on its own the next time the app opens, or tap Restore Purchases."
            return nil
        }
    }

    private struct SignedTransaction: Encodable, Sendable {
        let signedTransaction: String
    }

    private struct PlanStatus: Decodable, Sendable {
        let isPro: Bool
    }
}

extension Product.SubscriptionPeriod {
    /// "2 weeks", "1 month", "7 days".
    var spelledOut: String? {
        let unit: String
        switch self.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: return nil
        }
        return "\(value) \(unit)\(value == 1 ? "" : "s")"
    }
}

extension Product {
    /// "$39.99 a year", "$3.99 a month".
    var pricePerPeriod: String {
        guard let period = subscription?.subscriptionPeriod else { return displayPrice }
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: return displayPrice
        }
        return period.value == 1 ? "\(displayPrice) a \(unit)" : "\(displayPrice) every \(period.value) \(unit)s"
    }
}
