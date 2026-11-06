# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkey sign-in", type: :request do
  let(:user) { create(:user) }
  let!(:credential) { register_passkey(user) }

  def start_sign_in(params = {})
    get new_passkeys_session_path, params: params, as: :json
    JSON.parse(response.body)
  end

  def finish_sign_in(assertion, extra = {})
    post passkeys_sessions_path, params: assertion.merge(extra), as: :json
  end

  def signed_in?
    get security_path
    response.status == 200
  end

  describe "GET /passkeys/sessions/new" do
    it "asks for a discoverable passkey with user verification" do
      options = start_sign_in

      expect(response).to have_http_status(:ok)
      expect(options["challenge"]).to be_present
      expect(options["allowCredentials"]).to eq([])
      expect(options["userVerification"]).to eq("required")
    end

    it "does not reveal an account's passkeys when given its email" do
      known = start_sign_in(email: user.email)
      unknown = start_sign_in(email: "nobody@example.com")

      expect(known["allowCredentials"]).to eq([])
      expect(known.keys).to match_array(unknown.keys)
      expect(response.body).not_to include(credential.external_id)
    end
  end

  describe "POST /passkeys/sessions" do
    it "signs in the passkey's owner and updates the sign count" do
      options = start_sign_in
      finish_sign_in(passkey_assertion(challenge: options["challenge"], user_handle: user.id.to_s))

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("status" => "ok", "redirect_url" => "/")
      expect(credential.reload.sign_count).to be > 0
      expect(signed_in?).to be(true)
    end

    it "returns to the page that required sign-in" do
      get security_path
      expect(response).to redirect_to(new_user_session_path)

      options = start_sign_in
      finish_sign_in(passkey_assertion(challenge: options["challenge"], user_handle: user.id.to_s))

      expect(JSON.parse(response.body)["redirect_url"]).to eq(security_path)
    end

    it "rejects a passkey that skipped user verification" do
      options = start_sign_in
      finish_sign_in(passkey_assertion(challenge: options["challenge"], user_handle: user.id.to_s, user_verified: false))

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to eq("errors" => ["Authentication failed"])
      expect(signed_in?).to be(false)
    end

    it "rejects an assertion whose user handle belongs to someone else" do
      other = create(:user)
      options = start_sign_in
      finish_sign_in(passkey_assertion(challenge: options["challenge"], user_handle: other.id.to_s))

      expect(response).to have_http_status(:unprocessable_content)
      expect(signed_in?).to be(false)
    end

    it "rejects an assertion without a user handle" do
      options = start_sign_in
      finish_sign_in(passkey_assertion(challenge: options["challenge"], user_handle: nil))

      expect(response).to have_http_status(:unprocessable_content)
      expect(signed_in?).to be(false)
    end

    it "rejects a passkey this site never registered" do
      stranger = WebAuthn::FakeClient.new(WebAuthn.configuration.allowed_origins.first)
      stranger_challenge = WebAuthn.configuration.encoder.encode(SecureRandom.random_bytes(32))
      stranger.create(challenge: stranger_challenge, user_verified: true)

      options = start_sign_in
      finish_sign_in(passkey_assertion(challenge: options["challenge"], user_handle: user.id.to_s, client: stranger))

      expect(response).to have_http_status(:unprocessable_content)
      expect(signed_in?).to be(false)
    end

    it "uses up the challenge on a failed attempt" do
      options = start_sign_in
      finish_sign_in(passkey_assertion(challenge: options["challenge"], user_handle: user.id.to_s, user_verified: false))
      expect(response).to have_http_status(:unprocessable_content)

      finish_sign_in(passkey_assertion(challenge: options["challenge"], user_handle: user.id.to_s))

      expect(response).to have_http_status(:unprocessable_content)
      expect(signed_in?).to be(false)
    end

    it "rejects an assertion when no sign-in was started" do
      finish_sign_in(passkey_assertion(challenge: WebAuthn.configuration.encoder.encode("x" * 32), user_handle: user.id.to_s))

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a malformed assertion without an error page" do
      start_sign_in
      post passkeys_sessions_path, params: { id: "not-base64!", rawId: "%%%", type: "public-key", response: {} }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
