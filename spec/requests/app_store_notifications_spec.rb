# frozen_string_literal: true

require "rails_helper"

# POST /app_store/notifications: App Store Server Notifications V2.
RSpec.describe "App Store Server Notifications", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:purchase) { apple_transaction(user: user) }

  def deliver(type, transaction, **options)
    payload = apple_notification(type, transaction, **options)
    post "/app_store/notifications", params: { signedPayload: apple_pki.sign(payload) }.to_json,
                                     headers: { "Content-Type" => "application/json" }
    payload
  end

  # The account bought in the app (a SUBSCRIBED notification, with Apple's API agreeing).
  def subscribe!
    stub_apple_status(purchase)
    with_app_store_api { deliver("SUBSCRIBED", purchase, subtype: "INITIAL_BUY", renewal: apple_renewal(purchase), status: 1) }
    expect(user.reload.plan).to eq("PRO Monthly Apple")
  end

  # Apple's next answer about the subscription, and a notification prompting us to ask.
  def apple_now(type, transaction, status:, renewal: apple_renewal(transaction), subtype: nil)
    stub_apple_status(transaction, status: status, renewal: renewal)
    with_app_store_api { deliver(type, transaction, subtype: subtype, renewal: renewal, status: status) }
  end

  def later(seconds = 1, **overrides)
    purchase.merge("signedDate" => ms(seconds.seconds.from_now)).merge(overrides.transform_keys(&:to_s))
  end

  it "answers 200 and records the notification once" do
    subscribe!
    expect(response).to have_http_status(:ok)
    expect(AppStoreNotification.sole).to have_attributes(notification_type: "SUBSCRIBED", subtype: "INITIAL_BUY",
                                                         original_transaction_id: "1000000001", environment: "Sandbox")
    expect(AppStoreNotification.sole.processed_at).to be_present
  end

  it "makes PRO from a SUBSCRIBED notification that arrives before the app reports the purchase" do
    subscribe!
    expect(AppleSubscription.sole.user).to eq(user)
  end

  describe "renewal" do
    it "extends the paid period and keeps PRO" do
      subscribe!
      renewed = later(transactionId: "2000000002", purchaseDate: ms(1.month.from_now), expiresDate: ms(2.months.from_now))
      apple_now("DID_RENEW", renewed, status: 1)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
      expect(AppleSubscription.sole.expires_at).to be_within(1.second).of(2.months.from_now)
      expect(AppleSubscription.sole.last_transaction_id).to eq("2000000002")
    end

    it "records each production renewal's payment once" do
      allow(AppStore).to receive(:allowed_environments).and_return(%w[Production Sandbox])
      purchase.merge!("environment" => "Production")
      subscribe!
      renewed = later(transactionId: "2000000002", purchaseDate: ms(1.month.from_now), expiresDate: ms(2.months.from_now))
      apple_now("DID_RENEW", renewed, status: 1)
      expect(user.payments.pluck(:apple_transaction_id)).to contain_exactly(purchase["transactionId"], "2000000002")
    end
  end

  describe "expiry" do
    it "turns an expired subscription back to Free and emails the downgrade" do
      subscribe!
      expired = later(expiresDate: ms(1.minute.ago))
      expect do
        apple_now("EXPIRED", expired, status: 2, subtype: "VOLUNTARY", renewal: apple_renewal(expired, autoRenewStatus: 0, expirationIntent: 1))
      end.to have_enqueued_mail(UserMailer, :downgraded)
      expect(user.reload.plan).to eq("Free")
    end

    it "keeps PRO while auto-renew is off but the paid period isn't over" do
      subscribe!
      apple_now("DID_CHANGE_RENEWAL_STATUS", later, status: 1, subtype: "AUTO_RENEW_DISABLED", renewal: apple_renewal(purchase, autoRenewStatus: 0))
      expect(user.reload.plan).to eq("PRO Monthly Apple")
      expect(AppleSubscription.sole.auto_renew).to be(false)
    end
  end

  describe "grace period and billing retry" do
    it "keeps PRO through the billing grace period" do
      subscribe!
      lapsed = later(expiresDate: ms(1.minute.ago))
      renewal = apple_renewal(lapsed, isInBillingRetryPeriod: true, gracePeriodExpiresDate: ms(16.days.from_now))
      apple_now("DID_FAIL_TO_RENEW", lapsed, status: 4, subtype: "GRACE_PERIOD", renewal: renewal)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
      expect(AppleSubscription.sole).to be_in_grace_period
    end

    it "ends PRO when the grace period runs out without payment" do
      subscribe!
      lapsed = later(expiresDate: ms(17.days.ago))
      renewal = apple_renewal(lapsed, isInBillingRetryPeriod: true, gracePeriodExpiresDate: ms(1.day.ago))
      apple_now("GRACE_PERIOD_EXPIRED", lapsed, status: 3, renewal: renewal)
      expect(user.reload.plan).to eq("Free")
    end

    it "gives no PRO during billing retry without a grace period" do
      subscribe!
      lapsed = later(expiresDate: ms(1.minute.ago))
      apple_now("DID_FAIL_TO_RENEW", lapsed, status: 3, renewal: apple_renewal(lapsed, isInBillingRetryPeriod: true))
      expect(user.reload.plan).to eq("Free")
    end

    it "gives PRO back when a retry succeeds" do
      subscribe!
      lapsed = later(expiresDate: ms(1.minute.ago))
      apple_now("DID_FAIL_TO_RENEW", lapsed, status: 3, renewal: apple_renewal(lapsed, isInBillingRetryPeriod: true))
      recovered = later(2, transactionId: "2000000003", expiresDate: ms(1.month.from_now))
      apple_now("DID_RENEW", recovered, status: 1, subtype: "BILLING_RECOVERY")
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end
  end

  describe "refunds and revocation" do
    it "ends PRO at once on a refund, before the paid period is over" do
      subscribe!
      refunded = later(revocationDate: ms(Time.current), revocationReason: 0)
      apple_now("REFUND", refunded, status: 5)
      expect(user.reload.plan).to eq("Free")
      expect(AppleSubscription.sole.revoked_at).to be_present
    end

    it "gives PRO back when a refund is reversed" do
      subscribe!
      apple_now("REFUND", later(revocationDate: ms(Time.current)), status: 5)
      apple_now("REFUND_REVERSED", later(2), status: 1)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end

    it "ends PRO on REVOKE" do
      subscribe!
      apple_now("REVOKE", later(revocationDate: ms(Time.current)), status: 5)
      expect(user.reload.plan).to eq("Free")
    end
  end

  describe "upgrade and downgrade" do
    it "moves to yearly at once on an upgrade" do
      subscribe!
      yearly = later(transactionId: "2000000004", productId: AppStore::YEARLY_PRODUCT_ID, expiresDate: ms(1.year.from_now))
      apple_now("DID_CHANGE_RENEWAL_PREF", yearly, status: 1, subtype: "UPGRADE")
      expect(user.reload.plan).to eq("PRO Yearly Apple")
    end

    it "ignores the upgraded-from transaction if it comes after the new one" do
      subscribe!
      yearly = later(2, transactionId: "2000000004", productId: AppStore::YEARLY_PRODUCT_ID, expiresDate: ms(1.year.from_now))
      apple_now("DID_CHANGE_RENEWAL_PREF", yearly, status: 1, subtype: "UPGRADE")
      # No API this time: only the stale, upgraded-away monthly transaction to go on.
      deliver("DID_CHANGE_RENEWAL_PREF", later(3, isUpgraded: true, revocationDate: ms(Time.current)), status: 5)
      expect(user.reload.plan).to eq("PRO Yearly Apple")
    end

    it "stays yearly until the renewal on a downgrade, then becomes monthly" do
      purchase.merge!("productId" => AppStore::YEARLY_PRODUCT_ID, "expiresDate" => ms(1.year.from_now))
      stub_apple_status(purchase)
      with_app_store_api { deliver("SUBSCRIBED", purchase, renewal: apple_renewal(purchase), status: 1) }
      expect(user.reload.plan).to eq("PRO Yearly Apple")

      apple_now("DID_CHANGE_RENEWAL_PREF", later, status: 1, subtype: "DOWNGRADE",
                                                  renewal: apple_renewal(purchase, autoRenewProductId: AppStore::MONTHLY_PRODUCT_ID))
      expect(user.reload.plan).to eq("PRO Yearly Apple")
      expect(AppleSubscription.sole.auto_renew_product_id).to eq(AppStore::MONTHLY_PRODUCT_ID)

      monthly = later(2, transactionId: "2000000005", productId: AppStore::MONTHLY_PRODUCT_ID, expiresDate: ms(13.months.from_now))
      apple_now("DID_RENEW", monthly, status: 1)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end
  end

  describe "replays and ordering" do
    it "falls back to the notification's own state when Apple's answer doesn't check out" do
      # Apple's API answers for the wrong environment (a misrouted request, say).
      stub_request(:get, %r{api\.storekit-sandbox\.itunes\.apple\.com}).to_return(
        status: 200, headers: { "Content-Type" => "application/json" },
        body: { environment: "Production", bundleId: AppStore::BUNDLE_ID, data: [] }.to_json
      )
      with_app_store_api { deliver("SUBSCRIBED", purchase, renewal: apple_renewal(purchase), status: 1) }
      expect(response).to have_http_status(:ok)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end

    it "does nothing with a notification it has already processed" do
      payload = apple_notification("SUBSCRIBED", purchase, status: 1)
      stub = stub_apple_status(purchase)
      with_app_store_api do
        2.times do
          post "/app_store/notifications", params: { signedPayload: apple_pki.sign(payload) }.to_json,
                                           headers: { "Content-Type" => "application/json" }
          expect(response).to have_http_status(:ok)
        end
      end
      expect(stub).to have_been_requested.once
      expect(AppStoreNotification.count).to eq(1)
    end

    it "uses Apple's current state whatever order notifications come in" do
      subscribe!
      # Apple now says it's expired; a stale DID_RENEW arrives late.
      expired = later(expiresDate: ms(1.minute.ago))
      stub_apple_status(expired, status: 2, renewal: apple_renewal(expired, autoRenewStatus: 0))
      with_app_store_api { deliver("DID_RENEW", purchase, status: 1) }
      expect(user.reload.plan).to eq("Free")
    end

    it "without Apple's API, ignores a notification signed before the state it already has" do
      deliver("SUBSCRIBED", purchase, renewal: apple_renewal(purchase), status: 1)
      expired = later(expiresDate: ms(1.minute.ago))
      deliver("EXPIRED", expired, renewal: apple_renewal(expired, autoRenewStatus: 0), status: 2)
      expect(user.reload.plan).to eq("Free")

      # The earlier DID_RENEW, redelivered after the EXPIRED.
      deliver("DID_RENEW", purchase.merge("signedDate" => ms(1.minute.ago)), renewal: apple_renewal(purchase), status: 1)
      expect(user.reload.plan).to eq("Free")
    end

    it "asks Apple to redeliver when its API is down, after recording what the notification says" do
      stub_request(:get, %r{api\.storekit-sandbox\.itunes\.apple\.com}).to_return(status: 500)
      with_app_store_api { deliver("SUBSCRIBED", purchase, renewal: apple_renewal(purchase), status: 1) }
      expect(response).to have_http_status(:service_unavailable)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
      expect(AppStoreNotification.sole.processed_at).to be_nil

      stub_apple_status(purchase)
      payload_uuid = AppStoreNotification.sole.notification_uuid
      with_app_store_api { deliver("SUBSCRIBED", purchase, uuid: payload_uuid, renewal: apple_renewal(purchase), status: 1) }
      expect(response).to have_http_status(:ok)
      expect(AppStoreNotification.sole.processed_at).to be_present
    end

    it "records a notification for a subscription no account has claimed, for the app to claim later" do
      deliver("SUBSCRIBED", apple_transaction(appAccountToken: nil), status: 1)
      expect(response).to have_http_status(:ok)
      expect(AppleSubscription.sole.user).to be_nil
    end
  end

  describe "family sharing" do
    it "gives no PRO to a family member" do
      deliver("SUBSCRIBED", apple_transaction(user: user, inAppOwnershipType: "FAMILY_SHARED"), status: 1)
      expect(response).to have_http_status(:ok)
      expect(user.reload.plan).to eq("Free")
      expect(AppleSubscription.count).to eq(0)
    end
  end

  describe "accounts that pay on the web" do
    it "never changes their plan" do
      user.update!(plan: "PRO Monthly Gumroad")
      deliver("SUBSCRIBED", purchase, status: 1)
      deliver("EXPIRED", later(expiresDate: ms(1.minute.ago)), status: 2)
      expect(user.reload.plan).to eq("PRO Monthly Gumroad")
    end
  end

  describe "sandbox and production" do
    it "asks the sandbox API about sandbox purchases and the production API about production ones" do
      allow(AppStore).to receive(:allowed_environments).and_return(%w[Production Sandbox])
      production = apple_transaction(user: user, environment: "Production", originalTransactionId: "1000000777")
      prod_stub = stub_apple_status(production)
      sandbox_stub = stub_apple_status(purchase)
      with_env("APP_STORE_APP_APPLE_ID" => "1234567890") do
        with_app_store_api do
          deliver("SUBSCRIBED", production, status: 1)
          deliver("SUBSCRIBED", purchase, status: 1)
        end
      end
      expect(prod_stub).to have_been_requested.once
      expect(sandbox_stub).to have_been_requested.once
      expect(AppleSubscription.pluck(:environment)).to contain_exactly("Production", "Sandbox")
    end

    it "refuses a production notification for another app ID" do
      allow(AppStore).to receive(:allowed_environments).and_return(%w[Production Sandbox])
      with_env("APP_STORE_APP_APPLE_ID" => "999") do
        deliver("SUBSCRIBED", apple_transaction(user: user, environment: "Production"), status: 1)
      end
      # Genuinely Apple's, so 200 (no redelivery), but nothing is applied.
      expect(response).to have_http_status(:ok)
      expect(user.reload.plan).to eq("Free")
    end

    it "refuses sandbox notifications when sandbox is switched off" do
      with_env("APP_STORE_ALLOW_SANDBOX" => "false") { deliver("SUBSCRIBED", purchase, status: 1) }
      expect(response).to have_http_status(:ok)
      expect(AppleSubscription.count).to eq(0)
      expect(user.reload.plan).to eq("Free")
    end

    it "refuses production notifications outside production" do
      deliver("SUBSCRIBED", apple_transaction(user: user, environment: "Production"), status: 1)
      expect(response).to have_http_status(:ok)
      expect(user.reload.plan).to eq("Free")
    end

    it "takes no PRO from a notification about a product it doesn't sell" do
      deliver("SUBSCRIBED", apple_transaction(user: user, productId: "me.dabble.ios.other"), status: 1)
      expect(response).to have_http_status(:ok)
      expect(AppStoreNotification.sole.processed_at).to be_present
      expect(user.reload.plan).to eq("Free")
    end
  end

  describe "what isn't a real notification" do
    it "accepts Apple's TEST notification and does nothing with it" do
      payload = apple_notification("TEST", purchase).tap { |p| p["data"].delete("signedTransactionInfo") }
      post "/app_store/notifications", params: { signedPayload: apple_pki.sign(payload) }.to_json,
                                       headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(AppleSubscription.count).to eq(0)
    end

    it "refuses one not signed through Apple's chain" do
      forged = AppStoreHelpers::FakeApplePki.new.sign(apple_notification("SUBSCRIBED", purchase, status: 1))
      post "/app_store/notifications", params: { signedPayload: forged }.to_json, headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:bad_request)
      expect(AppStoreNotification.count).to eq(0)
    end

    it "refuses a genuine notification carrying a forged transaction" do
      payload = apple_notification("SUBSCRIBED", purchase, status: 1)
      payload["data"]["signedTransactionInfo"] = AppStoreHelpers::FakeApplePki.new.sign(purchase)
      post "/app_store/notifications", params: { signedPayload: apple_pki.sign(payload) }.to_json,
                                       headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:bad_request)
      expect(user.reload.plan).to eq("Free")
    end

    it "refuses another app's notification" do
      payload = apple_notification("SUBSCRIBED", purchase, status: 1)
      payload["data"]["bundleId"] = "com.example.other"
      post "/app_store/notifications", params: { signedPayload: apple_pki.sign(payload) }.to_json,
                                       headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(AppStoreNotification.count).to eq(0)
      expect(user.reload.plan).to eq("Free")
    end

    it "refuses junk" do
      post "/app_store/notifications", params: "not json", headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:bad_request)
      post "/app_store/notifications", params: { signedPayload: 1 }.to_json, headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:bad_request)
      post "/app_store/notifications", params: { signedPayload: "x" * 70_000 }.to_json, headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:content_too_large)
    end
  end
end
