# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin access", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:user, admin: true) }

  # Unmatched routes render 404 as in production instead of raising.
  def with_production_exceptions
    env_config = Rails.application.env_config
    previous = env_config['action_dispatch.show_exceptions']
    env_config['action_dispatch.show_exceptions'] = :all
    yield
  ensure
    env_config['action_dispatch.show_exceptions'] = previous
  end

  def verify_passkey(user = admin, client: passkey_client)
    get options_passkeys_verification_path, as: :json
    options = JSON.parse(response.body)
    post passkeys_verification_path,
      params: passkey_assertion(challenge: options["challenge"], user_handle: user.id.to_s, client: client),
      as: :json
  end

  describe "passkey check for admins" do
    let!(:credential) { register_passkey(admin) }

    before { sign_in admin }

    it "sends an admin who signed in without a passkey to the passkey check" do
      get admin_users_path
      expect(response).to redirect_to(new_passkeys_verification_path)

      get entries_path
      expect(response).to redirect_to(new_passkeys_verification_path)
    end

    it "refuses non-HTML requests until the passkey is confirmed" do
      get admin_users_path, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "offers only the admin's own passkeys" do
      get options_passkeys_verification_path, as: :json
      options = JSON.parse(response.body)

      expect(options["userVerification"]).to eq("required")
      expect(options["allowCredentials"].map { |c| c["id"] }).to eq([credential.external_id])
    end

    it "lets the admin in after the passkey is confirmed, back to the page they asked for" do
      get admin_users_path
      verify_passkey

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("status" => "ok", "redirect_url" => admin_users_path)
      expect(credential.reload.sign_count).to be > 0

      get admin_users_path
      expect(response).to have_http_status(:ok)
    end

    it "asks again after 12 hours" do
      verify_passkey
      get admin_users_path
      expect(response).to have_http_status(:ok)

      travel(AdminAccess::PASSKEY_FRESHNESS + 1.minute) do
        get admin_users_path
        expect(response).to redirect_to(new_passkeys_verification_path)
      end
    end

    it "refuses another account's passkey" do
      other = create(:user)
      other_client = WebAuthn::FakeClient.new(WebAuthn.configuration.allowed_origins.first)
      register_passkey(other, client: other_client)

      verify_passkey(other, client: other_client)
      expect(response).to have_http_status(:unprocessable_content)

      get admin_users_path
      expect(response).to redirect_to(new_passkeys_verification_path)
    end

    it "refuses a reused challenge" do
      get options_passkeys_verification_path, as: :json
      challenge = JSON.parse(response.body)["challenge"]
      assertion = passkey_assertion(challenge: challenge, user_handle: admin.id.to_s)

      post passkeys_verification_path, params: assertion, as: :json
      expect(response).to have_http_status(:ok)

      post passkeys_verification_path, params: assertion, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "sends Sidekiq to the passkey check too" do
      get "/sidekiq"
      expect(response).to redirect_to("/passkeys/verification/new")
    end

    it "still lets the admin log out" do
      delete destroy_user_session_path
      expect(response).to redirect_to(root_path)
    end

    it "keeps the admin's last passkey" do
      verify_passkey
      delete passkeys_registration_path(credential)

      expect(response).to redirect_to(security_path)
      expect(flash[:alert]).to include("at least one passkey")
      expect(admin.webauthn_credentials.count).to eq(1)
    end
  end

  it "counts a passkey sign-in as the check" do
    register_passkey(admin)
    get new_passkeys_session_path, as: :json
    challenge = JSON.parse(response.body)["challenge"]
    post passkeys_sessions_path, params: passkey_assertion(challenge: challenge, user_handle: admin.id.to_s), as: :json
    expect(response).to have_http_status(:ok)

    get admin_users_path
    expect(response).to have_http_status(:ok)
  end

  it "sends an admin without a passkey to add one" do
    sign_in admin

    get admin_users_path
    expect(response).to redirect_to(security_path)
    expect(flash[:alert]).to include("need a passkey")

    get security_path
    expect(response).to have_http_status(:ok)

    get new_passkeys_registration_path, as: :json
    expect(response).to have_http_status(:ok)
  end

  it "leaves other accounts alone" do
    user = create(:user)
    client = WebAuthn::FakeClient.new(WebAuthn.configuration.allowed_origins.first)
    credential = register_passkey(user, client: client)
    register_passkey(user, client: WebAuthn::FakeClient.new(WebAuthn.configuration.allowed_origins.first))
    sign_in user

    get security_path
    expect(response).to have_http_status(:ok)

    delete passkeys_registration_path(credential)
    expect(user.webauthn_credentials.count).to eq(1)

    with_production_exceptions { get admin_users_path }
    expect(response).to have_http_status(:not_found)
  end

  describe "Cloudflare Access" do
    around { |example| with_production_exceptions { example.run } }

    let(:team_domain) { "dabble-test.cloudflareaccess.com" }
    let(:aud) { "test-aud-tag" }
    let(:key) { OpenSSL::PKey::RSA.generate(2048) }
    let(:jwk) { JWT::JWK.new(key, kid: "test-key") }
    let(:certs_url) { "https://#{team_domain}/cdn-cgi/access/certs" }

    def access_token(signing_key: jwk, **claims)
      payload = { aud: [aud], iss: "https://#{team_domain}", exp: 1.hour.from_now.to_i, iat: Time.now.to_i, email: "owner@example.com" }.merge(claims)
      JWT.encode(payload, signing_key.signing_key, "RS256", kid: signing_key[:kid])
    end

    def with_token(token)
      { "Cf-Access-Jwt-Assertion" => token }
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("CLOUDFLARE_ACCESS_TEAM_DOMAIN").and_return(team_domain)
      allow(ENV).to receive(:[]).with("CLOUDFLARE_ACCESS_AUD").and_return(aud)
      CloudflareAccess.reset_keys!
      stub_request(:get, certs_url).to_return(status: 200, body: { keys: [jwk.export] }.to_json,
                                              headers: { "Content-Type" => "application/json" })
      register_passkey(admin)
      sign_in admin
      verify_passkey
    end

    after { CloudflareAccess.reset_keys! }

    it "lets a request with a valid Access token through" do
      get admin_users_path, headers: with_token(access_token)
      expect(response).to have_http_status(:ok)
    end

    it "hides admin pages without a token" do
      get admin_users_path
      expect(response).to have_http_status(:not_found)

      get "/sidekiq"
      expect(response).to have_http_status(:not_found)

      get "/admin/oauth"
      expect(response).to have_http_status(:not_found)
    end

    it "refuses tokens for another Access application, expired tokens and forged tokens" do
      get admin_users_path, headers: with_token(access_token(aud: ["another-app"]))
      expect(response).to have_http_status(:not_found)

      get admin_users_path, headers: with_token(access_token(exp: 1.minute.ago.to_i))
      expect(response).to have_http_status(:not_found)

      forged = JWT::JWK.new(OpenSSL::PKey::RSA.generate(2048), kid: "test-key")
      get admin_users_path, headers: with_token(access_token(signing_key: forged))
      expect(response).to have_http_status(:not_found)

      get admin_users_path, headers: with_token(access_token(iss: "https://evil.cloudflareaccess.com"))
      expect(response).to have_http_status(:not_found)
    end

    it "refuses everything when Cloudflare's keys can't be fetched" do
      CloudflareAccess.reset_keys!
      stub_request(:get, certs_url).to_return(status: 500)

      get admin_users_path, headers: with_token(access_token)
      expect(response).to have_http_status(:not_found)
    end

    it "picks up a rotated signing key" do
      get admin_users_path, headers: with_token(access_token)
      expect(response).to have_http_status(:ok)

      rotated = JWT::JWK.new(OpenSSL::PKey::RSA.generate(2048), kid: "rotated-key")
      stub_request(:get, certs_url).to_return(status: 200, body: { keys: [jwk.export, rotated.export] }.to_json,
                                              headers: { "Content-Type" => "application/json" })

      travel(CloudflareAccess::REFETCH_INTERVAL + 1.second) do
        get admin_users_path, headers: with_token(access_token(signing_key: rotated))
        expect(response).to have_http_status(:ok)
      end
    end

    it "leaves the rest of the site alone" do
      get entries_path
      expect(response).not_to have_http_status(:not_found)
    end
  end
end

RSpec.describe AdminAccess do
  let(:user) { build_stubbed(:user, admin: true) }

  it "ties the passkey check to one account" do
    session = {}
    described_class.record_passkey!(session, user)

    expect(described_class.passkey_fresh?(session, user)).to be(true)
    expect(described_class.passkey_fresh?(session, build_stubbed(:user, admin: true))).to be(false)
  end

  it "only keeps same-site return paths" do
    session = {}
    %w[https://evil.example //evil.example /\\evil.example].each do |path|
      described_class.remember_return_to!(session, path)
      expect(described_class.take_return_to!(session)).to be_nil
    end

    described_class.remember_return_to!(session, "/admin/users?page=2")
    expect(described_class.take_return_to!(session)).to eq("/admin/users?page=2")
  end
end
