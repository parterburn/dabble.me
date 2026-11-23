# frozen_string_literal: true

require "rails_helper"

# The web's subscribe and billing pages for an account paying through the App Store.
RSpec.describe PaymentsController, type: :controller do
  let(:user) { create(:user, plan: "PRO Monthly Apple") }

  before do
    AppleSubscription.create!(user: user, original_transaction_id: "1", environment: "Sandbox", product_id: AppStore::MONTHLY_PRODUCT_ID,
                              status: 1, expires_at: 1.week.from_now, ownership_type: "PURCHASED", state_signed_at: Time.current)
    sign_in user
  end

  it "won't start a Stripe checkout while an App Store subscription is active, so nobody pays twice" do
    expect(Stripe::Checkout::Session).not_to receive(:create)
    get :checkout, params: { plan: "yearly" }
    expect(response).to redirect_to(settings_path)
    expect(flash[:notice]).to include("App Store")
  end

  it "lets someone who cancelled in the App Store subscribe on the web" do
    AppleSubscription.sole.update!(auto_renew: false)
    allow(Stripe::Checkout::Session).to receive(:create).and_return(double(url: "https://checkout.stripe.com/x"))
    get :checkout, params: { plan: "yearly" }
    expect(response).to redirect_to("https://checkout.stripe.com/x")
  end

  it "sends the billing link to Apple's subscription page" do
    get :billing
    expect(response).to redirect_to("https://apps.apple.com/account/subscriptions")
  end
end
