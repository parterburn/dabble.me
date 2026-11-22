# frozen_string_literal: true

require "rails_helper"

RSpec.describe "iOS app: adding a passkey (/api/v1/passkeys)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:mobile_app) { MobileApp.ensure_application! }
  let(:password) { "correct-horse-battery" }
  let!(:user) { create(:user, email: "writer@example.com", password: password) }
  let(:token) { MobileApp.issue_token!(user) }
  let(:headers) { { "Authorization" => "Bearer #{token.plaintext_token}" } }

  def json
    JSON.parse(response.body)
  end

  def start
    get "/api/v1/passkeys/new", headers: headers, as: :json
    JSON.parse(response.body)
  end

  def add(options, user_verified: true, **auth)
    attestation = passkey_client.create(challenge: options["challenge"], user_verified: user_verified)
    post "/api/v1/passkeys", params: { challenge_token: options["challenge_token"], credential: attestation, **auth },
                             headers: headers, as: :json
  end

  describe "the sign-in answer" do
    it "carries a setup token after a password sign-in to an account with no passkey" do
      post "/api/v1/session", params: { email: user.email, password: password }, as: :json
      expect(json["passkey_setup_token"]).to be_present
    end

    it "carries one after sign-up" do
      post "/api/v1/registration", params: { email: "new@example.com", password: "a-good-password" }, as: :json
      expect(json["passkey_setup_token"]).to be_present
    end

    it "carries none once the account has a passkey" do
      register_passkey(user)
      post "/api/v1/session", params: { email: user.email, password: password }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json).not_to have_key("passkey_setup_token")
    end
  end

  it "says in /me whether the account has a passkey" do
    get "/api/v1/me", headers: headers
    expect(json["has_passkey"]).to be(false)

    register_passkey(user)
    get "/api/v1/me", headers: headers
    expect(json["has_passkey"]).to be(true)
  end

  it "hands out options for a discoverable passkey whose handle is the account's id" do
    options = start
    expect(response).to have_http_status(:ok)
    expect(options["rp_id"]).to eq(WebAuthn.configuration.rp_id)
    expect(options["user_name"]).to eq(user.email)
    expect(Base64.urlsafe_decode64(options["user_id"])).to eq(user.id.to_s)
    expect(options["challenge_token"]).to be_present
  end

  it "adds the passkey with the sign-in's setup token, emails about it, and the passkey signs in" do
    setup = Api::V1::PasskeysController.setup_token_for(user)

    expect { add(start, setup_token: setup, nickname: "iPhone") }
      .to change { user.webauthn_credentials.count }.by(1)
      .and have_enqueued_mail(UserMailer, :passkey_added)
    expect(response).to have_http_status(:created)
    expect(user.webauthn_credentials.last.nickname).to eq("iPhone")

    get "/api/v1/session/passkey", as: :json
    challenge = json
    assertion = passkey_assertion(challenge: challenge["challenge"], user_handle: user.id.to_s)
    post "/api/v1/session/passkey", params: { challenge_token: challenge["challenge_token"], credential: assertion }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it "adds it with the password instead" do
    expect { add(start, current_password: password) }.to change { user.webauthn_credentials.count }.by(1)
  end

  it "refuses without the password or a setup token" do
    expect { add(start) }.not_to change(WebauthnCredential, :count)
    expect(response).to have_http_status(:forbidden)
    expect(json["error"]).to eq("incorrect_password")
  end

  it "refuses a wrong password" do
    expect { add(start, current_password: "nope-nope") }.not_to change(WebauthnCredential, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "refuses an expired setup token" do
    setup = Api::V1::PasskeysController.setup_token_for(user)
    travel Api::V1::PasskeysController::SETUP_WINDOW + 1.minute do
      # (A fresh challenge, so only the setup token is stale.)
      expect { add(start, setup_token: setup) }.not_to change(WebauthnCredential, :count)
    end
    expect(response).to have_http_status(:forbidden)
  end

  it "refuses another account's setup token" do
    other = create(:user)
    expect { add(start, setup_token: Api::V1::PasskeysController.setup_token_for(other)) }
      .not_to change(WebauthnCredential, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "refuses a passkey that didn't verify the person" do
    expect { add(start, current_password: password, user_verified: false) }.not_to change(WebauthnCredential, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]).to eq("passkey_not_added")
  end

  it "refuses a challenge handed to another account" do
    other = create(:user)
    other_headers = { "Authorization" => "Bearer #{MobileApp.issue_token!(other).plaintext_token}" }
    get "/api/v1/passkeys/new", headers: other_headers, as: :json
    expect { add(json, current_password: password) }.not_to change(WebauthnCredential, :count)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "spends a challenge once" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    options = start
    add(options, current_password: password)
    expect(response).to have_http_status(:created)

    second = WebAuthn::FakeClient.new(WebAuthn.configuration.allowed_origins.first)
    attestation = second.create(challenge: options["challenge"], user_verified: true)
    post "/api/v1/passkeys", params: { challenge_token: options["challenge_token"], credential: attestation, current_password: password },
                             headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "needs an app token" do
    get "/api/v1/passkeys/new", as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
