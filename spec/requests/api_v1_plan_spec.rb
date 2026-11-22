# frozen_string_literal: true

require "rails_helper"

# GET /api/v1/plan: the iOS app's Plan page.
RSpec.describe "The app's Plan page", type: :request do
  let(:user) { create(:user) }
  let(:mobile_app) { MobileApp.ensure_application! }

  def auth(account)
    token = Doorkeeper::AccessToken.create!(application: mobile_app, resource_owner_id: account.id, scopes: MobileApp::SCOPE)
    { "Authorization" => "Bearer #{token.plaintext_token}" }
  end

  def json = JSON.parse(response.body)

  def stripe_subscriptions(*subscriptions)
    Stripe::ListObject.construct_from(object: "list", data: subscriptions.map { |s| { object: "subscription" }.merge(s) })
  end

  def stripe_subscription(period_end:, status: "active", cancel_at_period_end: false, cancel_at: nil)
    { id: "sub_#{SecureRandom.hex(4)}", status: status, cancel_at_period_end: cancel_at_period_end, cancel_at: cancel_at,
      items: { object: "list", data: [{ object: "subscription_item", current_period_end: period_end.to_i }] } }
  end

  let(:renews) { Time.utc(2026, 12, 21, 18) }

  context "with a Stripe plan" do
    before { user.update!(plan: "PRO Monthly PayHere", stripe_id: "cus_123") }

    it "says when it renews" do
      allow(Stripe::Subscription).to receive(:list).with(customer: "cus_123", limit: 10)
                                                     .and_return(stripe_subscriptions(stripe_subscription(period_end: renews)))
      get "/api/v1/plan", headers: auth(user)
      expect(response).to have_http_status(:ok)
      expect(json).to include("plan" => "pro", "pro_source" => "web", "apple_subscription" => nil)
      expect(json["web_subscription"]).to eq("provider" => "Stripe", "expires_at" => renews.iso8601, "will_renew" => true)
    end

    it "says when it ends once it's cancelled in the billing portal" do
      allow(Stripe::Subscription).to receive(:list).and_return(stripe_subscriptions(
        stripe_subscription(period_end: renews, cancel_at_period_end: true),
        stripe_subscription(period_end: renews + 1.year, status: "canceled")
      ))
      get "/api/v1/plan", headers: auth(user)
      expect(json["web_subscription"]).to include("expires_at" => renews.iso8601, "will_renew" => false)
    end

    it "has no date when Stripe can't be reached" do
      allow(Stripe::Subscription).to receive(:list).and_raise(Stripe::APIConnectionError.new("down"))
      get "/api/v1/plan", headers: auth(user)
      expect(response).to have_http_status(:ok)
      expect(json["web_subscription"]).to be_nil
    end

    it "asks Stripe once while the answer is cached" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      allow(Stripe::Subscription).to receive(:list).and_return(stripe_subscriptions(stripe_subscription(period_end: renews)))
      2.times { get "/api/v1/plan", headers: auth(user) }
      expect(Stripe::Subscription).to have_received(:list).once
      expect(json["web_subscription"]["expires_at"]).to eq(renews.iso8601)
    end
  end

  it "doesn't ask Stripe about a free account, a plan billed elsewhere, or one without a customer" do
    expect(Stripe::Subscription).not_to receive(:list)
    get "/api/v1/plan", headers: auth(user)
    expect(json).to include("plan" => "free", "web_subscription" => nil)

    user.update!(plan: "PRO Yearly Gumroad")
    get "/api/v1/plan", headers: auth(user)
    expect(json).to include("pro_source" => "web", "web_subscription" => nil)

    user.update!(plan: "PRO Monthly PayHere", stripe_id: nil)
    get "/api/v1/plan", headers: auth(user)
    expect(json["web_subscription"]).to be_nil
  end

  it "needs a sign-in" do
    get "/api/v1/plan"
    expect(response).to have_http_status(:unauthorized)
  end
end
