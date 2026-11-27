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
        if let me = model.me, !me.isPro, me.sellsInApp {
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
                VStack(spacing: 2) {
                    Button("Restore Purchases") {
                        Task { await store.restore() }
                    }
                    .font(.subheadline)
                    // The password prompt is Apple's own (AppStore.sync), not Dabble Me's.
                    Text("Apple may ask you to sign in to your Apple Account.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
            // Inside a List row (Settings → Plan) every default-style button and link in the row
            // would answer a tap anywhere in it, so a tap on Restore Purchases opened the Privacy
            // Policy. Borderless buttons take only their own taps; the plan buttons keep their style.
            .buttonStyle(.borderless)
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
    /// When a plan bought on dabble.me renews (GET /api/v1/plan); nil until it's loaded.
    @State private var webSubscription: PlanDetails.WebSubscriptionInfo?

    var body: some View {
        List {
            if let me = model.me {
                if me.isProThroughApple {
                    Section {
                        LabeledContent("Plan", value: "PRO")
                        // In a grace period the paid-to date has passed: the footer says what to do.
                        if me.appleSubscription?.inGracePeriod != true,
                           let renewal = renewalText(me.appleSubscription?.expiresAt, willRenew: me.appleSubscription?.willRenew) {
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
                        if let renewal = renewalText(webSubscription?.expiresAt, willRenew: webSubscription?.willRenew) {
                            LabeledContent(renewal.label, value: renewal.date)
                        }
                        // PRO on dabble.me and an App Store subscription too: that one can be cancelled here.
                        if me.appleSubscription != nil {
                            Button("Manage App Store Subscription") { managing = true }
                        }
                    } footer: {
                        Text(me.appleSubscription != nil
                             ? "Your PRO subscription is through dabble.me. This Apple Account is also paying for PRO: cancel it in Manage App Store Subscription."
                             : "Your PRO subscription is through dabble.me, so there's nothing to buy here.")
                    }
                    .task { await loadWebSubscription() }
                } else if !me.sellsInApp {
                    Section {
                        LabeledContent("Plan", value: "Free")
                    } footer: {
                        Text("Dabble Me is closing, so PRO is no longer sold.")
                    }
                } else {
                    Section {
                        VStack(spacing: 16) {
                            Text("Dabble Me PRO adds search, Stats and Rewind, photos, editing, and email on the days you choose.")
                                .multilineTextAlignment(.center)
                            SubscribeOptions()
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
    }

    private func loadWebSubscription() async {
        // An older server has no /plan: the page shows the plan without a date.
        let details: PlanDetails? = try? await model.api.get("api/v1/plan")
        webSubscription = details?.webSubscription
    }

    private func renewalText(_ expiresAt: String?, willRenew: Bool?) -> (label: String, date: String)? {
        guard let raw = expiresAt, let date = ISO8601DateFormatter().date(from: raw) else { return nil }
        let formatted = date.formatted(date: .abbreviated, time: .omitted)
        return (willRenew == false ? "Ends" : "Renews", formatted)
    }
}

/// A Free account's line about a PRO feature ("… with Dabble Me PRO."), "Dabble Me PRO" in olive:
/// a tap opens Settings → Plan in a sheet, to upgrade. Plain words where the server can't take an
/// in-app purchase (Settings has no Plan page then either).
struct ProUpsellLine: View {
    /// The words before "Dabble Me PRO", and after it (usually a full stop).
    let before: String
    var after = "."
    @Environment(AppModel.self) private var model
    @State private var showingPlan = false

    private var opensPlan: Bool { model.me?.appleAccountToken != nil }

    private var text: Text {
        Text(before) + Text("Dabble Me PRO").foregroundStyle(opensPlan ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)) + Text(after)
    }

    var body: some View {
        if opensPlan {
            Button { showingPlan = true } label: {
                text.multilineTextAlignment(.leading).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your plan, to upgrade.")
            .sheet(isPresented: $showingPlan) {
                NavigationStack {
                    PlanView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingPlan = false }
                            }
                        }
                }
            }
        } else {
            text
        }
    }
}
