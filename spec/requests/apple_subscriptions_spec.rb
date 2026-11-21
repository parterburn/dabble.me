# frozen_string_literal: true

require "rails_helper"

# POST /api/v1/apple_subscriptions: the iOS app's purchase, restore and Transaction.updates.
RSpec.describe "Apple in-app purchases from the app", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:mobile_app) { MobileApp.ensure_application! }

  def auth(account)
    token = Doorkeeper::AccessToken.create!(application: mobile_app, resource_owner_id: account.id, scopes: MobileApp::SCOPE)
    { "Authorization" => "Bearer #{token.plaintext_token}" }
  end

  def json = JSON.parse(response.body)

  def post_transaction(transaction, as: user)
    post "/api/v1/apple_subscriptions", params: { signed_transaction: apple_pki.sign(transaction) }.to_json,
                                        headers: auth(as).merge("Content-Type" => "application/json")
  end

  describe "GET /api/v1/me" do
    it "gives the app a stable appAccountToken to buy with, and where PRO comes from" do
      get "/api/v1/me", headers: auth(user)
      token = json["apple_account_token"]
      expect(token).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      expect(json["pro_source"]).to be_nil
      expect(json["apple_subscription"]).to be_nil

      get "/api/v1/me", headers: auth(user)
      expect(json["apple_account_token"]).to eq(token)
    end

    it "says a web subscriber's PRO comes from the web" do
      user.update!(plan: "PRO Yearly PayHere")
      get "/api/v1/me", headers: auth(user)
      expect(json["pro_source"]).to eq("web")
    end
  end

  describe "a purchase" do
    it "makes a Free account PRO once Apple confirms it, and sends the thank-you email" do
      transaction = apple_transaction(user: user)
      stub = stub_apple_status(transaction)

      with_app_store_api do
        expect { post_transaction(transaction) }.to have_enqueued_mail(UserMailer, :thanks_for_paying)
      end

      expect(stub).to have_been_requested
      expect(response).to have_http_status(:ok)
      expect(json).to include("is_pro" => true, "pro_source" => "apple")
      expect(json["apple_subscription"]).to include("product_id" => AppStore::MONTHLY_PRODUCT_ID, "will_renew" => true, "sandbox" => true)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
      subscription = user.apple_subscriptions.sole
      expect(subscription).to have_attributes(original_transaction_id: "1000000001", status: 1, auto_renew: true)
    end

    it "makes it PRO Yearly for the yearly product" do
      transaction = apple_transaction(user: user, productId: AppStore::YEARLY_PRODUCT_ID, expiresDate: ms(1.year.from_now))
      stub_apple_status(transaction)
      with_app_store_api { post_transaction(transaction) }
      expect(user.reload.plan).to eq("PRO Yearly Apple")
    end

    it "uses Apple's state over the transaction the app sent" do
      sent = apple_transaction(user: user)
      # Apple says it has been refunded since.
      now = apple_transaction(user: user, transactionId: sent["transactionId"], revocationDate: ms(Time.current), revocationReason: 0,
                                          signedDate: ms(1.second.from_now))
      stub_apple_status(now, status: 5)
      with_app_store_api { post_transaction(sent) }
      expect(json["is_pro"]).to be(false)
      expect(user.reload.plan).to eq("Free")
    end

    it "uses the signed transaction itself while Apple's API isn't set up" do
      post_transaction(apple_transaction(user: user))
      expect(response).to have_http_status(:ok)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end

    it "uses the signed transaction itself when Apple's API is down" do
      transaction = apple_transaction(user: user)
      stub_request(:get, %r{api\.storekit-sandbox\.itunes\.apple\.com}).to_return(status: 503)
      with_app_store_api { post_transaction(transaction) }
      expect(response).to have_http_status(:ok)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end

    it "doesn't record payments for sandbox purchases" do
      post_transaction(apple_transaction(user: user))
      expect(Payment.count).to eq(0)
    end

    it "records one payment per production transaction, in dollars" do
      allow(AppStore).to receive(:allowed_environments).and_return(%w[Production Sandbox])
      transaction = apple_transaction(user: user, environment: "Production", transactionId: "2000000099")
      post_transaction(transaction)
      post_transaction(transaction)
      payment = user.payments.sole
      expect(payment).to have_attributes(apple_transaction_id: "2000000099", amount: 3.99, comments: "Apple Monthly")
    end

    it "records a payment in another currency with no dollar amount" do
      allow(AppStore).to receive(:allowed_environments).and_return(%w[Production Sandbox])
      post_transaction(apple_transaction(user: user, environment: "Production", price: 600_000, currency: "JPY"))
      expect(user.payments.sole).to have_attributes(amount: 0, comments: "Apple Monthly (JPY 600.00)")
    end
  end

  describe "an account that's PRO through the web" do
    it "keeps its web plan, and Paul hears about the double charge" do
      allow(AppStore).to receive(:allowed_environments).and_return(%w[Production Sandbox])
      user.update!(plan: "PRO Yearly PayHere", stripe_id: "cus_123")
      expect do
        post_transaction(apple_transaction(user: user, environment: "Production"))
      end.to have_enqueued_mail(UserMailer, :apple_double_billing)
      expect(user.reload.plan).to eq("PRO Yearly PayHere")
      expect(json["pro_source"]).to eq("web")
    end

    it "is never downgraded by its Apple subscription ending" do
      user.update!(plan: "PRO Forever")
      post_transaction(apple_transaction(user: user, expiresDate: ms(1.minute.ago)))
      expect(user.reload.plan).to eq("PRO Forever")
    end

    it "moves to the Apple subscription when the web plan ends" do
      user.update!(plan: "PRO Monthly PayHere")
      post_transaction(apple_transaction(user: user))
      expect(user.reload.plan).to eq("PRO Monthly PayHere")

      user.update!(plan: "Free") # Stripe cancelled, or the expired-plan check
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end
  end

  describe "a purchase made for a different Dabble Me account" do
    let(:other) { create(:user, email: "someone@example.com") }

    it "is refused when the transaction names another account, and that account isn't changed" do
      post_transaction(apple_transaction(user: other))
      expect(response).to have_http_status(:conflict)
      expect(json["error"]).to eq("subscription_belongs_to_other_account")
      expect(json["message"]).to include("s***@example.com")
      expect(user.reload.plan).to eq("Free")
      expect(AppleSubscription.count).to eq(0)
    end

    it "is refused when the subscription is already linked to another account" do
      post_transaction(apple_transaction(user: other), as: other)
      expect(other.reload.plan).to eq("PRO Monthly Apple")

      # The same subscription, restored while signed in as someone else (a renewal from
      # iOS Settings carries no appAccountToken).
      post_transaction(apple_transaction(appAccountToken: nil, signedDate: ms(1.second.from_now)))
      expect(response).to have_http_status(:conflict)
      expect(user.reload.plan).to eq("Free")
      expect(other.reload.plan).to eq("PRO Monthly Apple")
      expect(AppleSubscription.sole.user).to eq(other)
    end

    it "moves to whoever buys again after it lapsed (the newest purchase names the account)" do
      post_transaction(apple_transaction(user: other, expiresDate: ms(1.minute.ago)), as: other)
      expect(other.reload.plan).to eq("Free")

      post_transaction(apple_transaction(user: user, signedDate: ms(1.second.from_now)))
      expect(response).to have_http_status(:ok)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
      expect(AppleSubscription.sole.user).to eq(user)
    end
  end

  describe "restore purchases" do
    it "links a subscription bought outside the app (no appAccountToken) to the account restoring it" do
      post_transaction(apple_transaction(appAccountToken: nil))
      expect(response).to have_http_status(:ok)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end

    it "is harmless to repeat" do
      transaction = apple_transaction(user: user)
      3.times { post_transaction(transaction) }
      expect(AppleSubscription.count).to eq(1)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end

    it "lets a new account restore the subscription of an account that was deleted" do
      old = create(:user)
      post_transaction(apple_transaction(user: old), as: old)
      old.update_column(:deleted_at, 2.hours.ago)
      DeleteUserJob.perform_now(old.id)
      expect(AppleSubscription.sole.user).to be_nil

      post_transaction(apple_transaction(appAccountToken: old.apple_account_token, signedDate: ms(1.second.from_now)))
      expect(response).to have_http_status(:ok)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end

    it "doesn't let an old copy of a transaction undo newer state" do
      newer = apple_transaction(user: user, revocationDate: ms(Time.current), signedDate: ms(Time.current))
      post_transaction(newer)
      expect(user.reload.plan).to eq("Free")

      post_transaction(apple_transaction(user: user, signedDate: ms(1.hour.ago)))
      expect(user.reload.plan).to eq("Free")
    end
  end

  describe "refusals" do
    it "refuses Family Sharing" do
      post_transaction(apple_transaction(user: user, inAppOwnershipType: "FAMILY_SHARED"))
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("family_sharing_not_supported")
      expect(user.reload.plan).to eq("Free")
    end

    {
      "another app's transaction" => { bundleId: "com.example.other" },
      "an unknown product" => { productId: "me.dabble.ios.pro.lifetime" },
      "a non-subscription" => { type: "Non-Consumable" },
      "Xcode's local StoreKit testing" => { environment: "Xcode" },
      "a production purchase on a non-production server" => { environment: "Production" }
    }.each do |what, overrides|
      it "refuses #{what}" do
        post_transaction(apple_transaction(user: user, **overrides))
        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]).to eq("invalid_transaction")
        expect(user.reload.plan).to eq("Free")
      end
    end

    it "refuses sandbox purchases when APP_STORE_ALLOW_SANDBOX is false" do
      with_env("APP_STORE_ALLOW_SANDBOX" => "false") { post_transaction(apple_transaction(user: user)) }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a transaction not signed through Apple's chain" do
      forged = AppStoreHelpers::FakeApplePki.new.sign(apple_transaction(user: user))
      post "/api/v1/apple_subscriptions", params: { signed_transaction: forged }.to_json,
                                          headers: auth(user).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.plan).to eq("Free")
    end

    it "refuses a missing or oversized transaction" do
      post "/api/v1/apple_subscriptions", params: {}.to_json, headers: auth(user).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:unprocessable_content)
      post "/api/v1/apple_subscriptions", params: { signed_transaction: "a" * 40_000 }.to_json,
                                          headers: auth(user).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "needs the app's sign-in" do
      post "/api/v1/apple_subscriptions", params: { signed_transaction: apple_pki.sign(apple_transaction(user: user)) }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
