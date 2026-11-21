import StoreKit
import SwiftUI

/// The in-app purchase of Dabble Me PRO: the two plans, Restore Purchases, and the terms Apple
/// asks for (guideline 3.1.2: what it costs and how often, that it renews, and links to the
/// Terms of Use and Privacy Policy). Shown only to a Free account the server can sell to; an
/// account that's PRO already, or whose Apple Account pays for another Dabble Me account,
/// gets no purchase buttons.
struct SubscribeOptions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.purchase) private var purchase

    var body: some View {
        let store = model.subscriptions
        if let me = model.me, !me.isPro, me.appleAccountToken != nil {
            VStack(spacing: 12) {
                if store.belongsToOtherAccount {
                    Text("This Apple Account already pays for Dabble Me PRO on a different Dabble Me account. Sign in to that account to use it.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                } else if store.products.isEmpty {
                    if store.productsFailed {
                        Text("The App Store isn't available right now. Try again in a moment.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                } else {
                    ForEach(store.products, id: \.id) { product in
                        planButton(product, store: store)
                    }
                }
                if let message = store.message {
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Button("Restore Purchases") {
                    Task { await store.restore() }
                }
                .font(.subheadline)
                Text(store.freeTrials.isEmpty
                     ? "PRO renews automatically until you cancel it. Cancel at least 24 hours before it renews in Settings → your name → Subscriptions."
                     : "After a free trial, you're charged unless you cancel at least 24 hours before it ends. PRO then renews automatically until you cancel it in Settings → your name → Subscriptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 16) {
                    Link("Terms of Use", destination: AppConfig.webURL("terms"))
                    Link("Privacy Policy", destination: AppConfig.webURL("privacy"))
                }
                .font(.caption)
            }
            .disabled(store.isWorking)
            .overlay {
                if store.isWorking { ProgressView() }
            }
            .task {
                await store.loadProducts()
                await store.checkEntitlements()
            }
        }
    }

    private func planButton(_ product: Product, store: SubscriptionStore) -> some View {
        let yearly = product.id == SubscriptionStore.yearlyID
        return Button {
            Task { await store.buy(product, with: purchase) }
        } label: {
            VStack(spacing: 2) {
                Text(product.displayName).font(.headline)
                if let trial = store.freeTrials[product.id] {
                    // Apple asks for the price after the trial to be as clear as the trial (3.1.2).
                    Text("\(trial), then \(product.pricePerPeriod)").font(.subheadline)
                } else {
                    Text(product.pricePerPeriod).font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(yearly ? Color.accentColor : Color.secondary)
        .accessibilityLabel([product.displayName, store.freeTrials[product.id], product.pricePerPeriod].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Settings → Plan: what the account has and where it's managed, or the purchase.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var managing = false
    /// The US storefront may also link to dabble.me's own checkout (guideline 3.1.1(a)).
    @State private var canLinkToWeb = false

    var body: some View {
        List {
            if let me = model.me {
                if me.isProThroughApple {
                    Section {
                        LabeledContent("Plan", value: "PRO")
                        if let renewal = renewalText(me.appleSubscription) {
                            LabeledContent(renewal.label, value: renewal.date)
                        }
                        Button("Manage Subscription") { managing = true }
                    } footer: {
                        Text(me.appleSubscription?.inGracePeriod == true
                             ? "The App Store couldn't renew your subscription. Update your payment details in Settings → your name → Subscriptions to keep PRO."
                             : "Billed by the App Store. Change or cancel it in Manage Subscription.")
                    }
                } else if me.isPro {
                    Section {
                        LabeledContent("Plan", value: "PRO")
                    } footer: {
                        Text("Your PRO subscription is through dabble.me, so there's nothing to buy here.")
                    }
                } else {
                    Section {
                        VStack(spacing: 16) {
                            Text("Dabble Me PRO adds search, Stats and Rewind, photos, editing, and email on the days you choose.")
                                .multilineTextAlignment(.center)
                            SubscribeOptions()
                            if canLinkToWeb {
                                Link(destination: AppConfig.webURL("subscribe")) {
                                    HStack(spacing: 8) {
                                        Text("Or subscribe on dabble.me")
                                        ExternalLinkIcon()
                                    }
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationTitle("Plan")
        .manageSubscriptionsSheet(isPresented: $managing)
        .onChange(of: managing) { _, isShowing in
            // A change made in Apple's sheet reaches the server by notification; reload after.
            if !isShowing { Task { await model.refresh() } }
        }
        .task { canLinkToWeb = await Storefront.current?.countryCode == "USA" }
    }

    private func renewalText(_ subscription: Me.AppleSubscriptionInfo?) -> (label: String, date: String)? {
        guard let subscription, let raw = subscription.expiresAt,
              let date = ISO8601DateFormatter().date(from: raw) else { return nil }
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        return (subscription.willRenew == false ? "Ends" : "Renews", formatted)
    }
}
