# frozen_string_literal: true

require "rails_helper"

# The page after a web sign-in that offers a passkey, once per browser (PasskeyOffer).
RSpec.describe "Offering a passkey after a web sign-in", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:password) { "correct-horse-battery" }
  let!(:user) { create(:user, email: "writer@example.com", password: password) }

  def skip_link
    Nokogiri::HTML(response.body).at_css("#passkey-offer-skip")["href"]
  end

  def sign_in_with_password(account = user)
    post user_session_path, params: { user: { email: account.email, password: password } }
  end

  it "stops at the offer after a password sign-in, then goes on to the journal" do
    sign_in_with_password
    expect(response).to redirect_to(passkeys_offer_path)

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add a passkey")
    expect(skip_link).to eq(root_path)
  end

  it "keeps where the sign-in was headed for Not now" do
    get "/entries/new"
    sign_in_with_password
    get passkeys_offer_path
    expect(skip_link).to eq("/entries/new")
  end

  it "shows once on a browser" do
    sign_in_with_password
    get passkeys_offer_path
    expect(cookies[PasskeyOffer.cookie_name(user)]).to be_present

    delete destroy_user_session_path
    sign_in_with_password
    expect(response).to redirect_to(root_path)
  end

  it "keeps one account's offer to that account on a shared browser" do
    other = create(:user, email: "partner@example.com", password: password)
    sign_in_with_password
    get passkeys_offer_path
    delete destroy_user_session_path

    sign_in_with_password(other)
    expect(response).to redirect_to(passkeys_offer_path)
  end

  it "isn't offered to an account that has a passkey" do
    register_passkey(user)
    sign_in_with_password
    expect(response).to redirect_to(root_path)

    get passkeys_offer_path
    expect(response).to redirect_to(root_path)
  end

  it "doesn't interrupt connecting an app" do
    authorize = "/oauth/authorize?client_id=abc&response_type=code"
    get authorize
    sign_in_with_password
    expect(response.location).not_to include(passkeys_offer_path)
  end

  it "isn't offered by visiting the sign-in page while already signed in" do
    sign_in_with_password
    travel(FreshSignIn::FRESH_FOR + 1.minute) do
      get new_user_session_path
      expect(response).to redirect_to(root_path)
    end
  end

  it "adds the passkey in a tap, with no password, just after signing in" do
    sign_in_with_password
    get passkeys_offer_path
    expect(response.body).to include('data-proof-needed="false"')

    get new_passkeys_registration_path, as: :json
    attestation = passkey_client.create(challenge: JSON.parse(response.body)["challenge"], user_verified: true)
    expect {
      post passkeys_registrations_path, params: attestation.merge(nickname: "Chrome on Mac"), as: :json
    }.to change { user.webauthn_credentials.count }.by(1)
    expect(response).to have_http_status(:ok)
  end

  it "asks for the password again once the sign-in isn't fresh" do
    sign_in_with_password
    travel(FreshSignIn::FRESH_FOR + 1.minute) do
      get passkeys_offer_path
      expect(response.body).to include('data-proof-needed="true"')

      get new_passkeys_registration_path, as: :json
      attestation = passkey_client.create(challenge: JSON.parse(response.body)["challenge"], user_verified: true)
      expect {
        post passkeys_registrations_path, params: attestation.merge(nickname: "Laptop"), as: :json
      }.not_to change { user.webauthn_credentials.count }
    end
  end

  it "isn't offered straight after sign-up" do
    stub_const("EmailSignIn::UNCLAIMED_FROM", 1.year.from_now)
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      post email_codes_path, params: { user: { email: "brandnew@example.com" }, intent: "sign_up" }
    end
    code = ActionMailer::Base.deliveries.last.subject[/\A\d{6}/]

    post verify_email_code_path, params: { code: code }
    expect(response).to redirect_to(root_path)
  end
end
