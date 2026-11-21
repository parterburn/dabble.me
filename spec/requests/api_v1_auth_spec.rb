# frozen_string_literal: true

require "rails_helper"

RSpec.describe "iOS app native sign-in, sign-up and account deletion", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:mobile_app) { MobileApp.ensure_application! }
  let(:password) { "correct-horse-battery" }
  let!(:user) { create(:user, email: "writer@example.com", password: password) }

  def json
    JSON.parse(response.body)
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  describe "POST /api/v1/session" do
    it "answers a right password with tokens the app API accepts" do
      post "/api/v1/session", params: { email: " Writer@Example.com ", password: password }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to include("token_type" => "Bearer", "scope" => MobileApp::SCOPE, "deletion_cancelled" => false)
      expect(json["access_token"]).to be_present
      expect(json["refresh_token"]).to be_present
      expect(json["expires_in"]).to eq(Doorkeeper.config.access_token_expires_in.to_i)

      token = Doorkeeper::AccessToken.last
      expect(token.application).to eq(mobile_app)
      expect(token.resource_owner_id).to eq(user.id)

      get "/api/v1/me", headers: bearer(json["access_token"])
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["email"]).to eq("writer@example.com")
    end

    it "gives back a refresh token that renews at /oauth/token" do
      post "/api/v1/session", params: { email: user.email, password: password }, as: :json
      refresh = json["refresh_token"]

      post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: refresh, client_id: MobileApp::CLIENT_ID }
      expect(response).to have_http_status(:ok)
      expect(json["access_token"]).to be_present
    end

    it "says the same thing for a wrong password and an unknown email" do
      post "/api/v1/session", params: { email: user.email, password: "nope-nope" }, as: :json
      expect(response).to have_http_status(:unauthorized)
      wrong_password = json

      post "/api/v1/session", params: { email: "nobody@example.com", password: "nope-nope" }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq(wrong_password)
      expect(json["error"]).to eq("invalid_credentials")
      expect(Doorkeeper::AccessToken.count).to eq(0)
    end

    context "with two-factor authentication on" do
      before do
        user.generate_otp_secret
        user.update!(otp_enabled: true, otp_enabled_on: Time.current)
      end

      it "asks for the code after the right password, and issues nothing yet" do
        post "/api/v1/session", params: { email: user.email, password: password }, as: :json
        expect(response).to have_http_status(:unauthorized)
        expect(json["error"]).to eq("otp_required")
        expect(Doorkeeper::AccessToken.count).to eq(0)
      end

      it "doesn't reveal that 2FA is on to someone without the password" do
        post "/api/v1/session", params: { email: user.email, password: "nope-nope" }, as: :json
        expect(json["error"]).to eq("invalid_credentials")
      end

      it "refuses a wrong code" do
        post "/api/v1/session", params: { email: user.email, password: password, otp_code: "000000" }, as: :json
        expect(response).to have_http_status(:unauthorized)
        expect(json["error"]).to eq("invalid_otp")
      end

      it "signs in with the password and a current code" do
        code = ROTP::TOTP.new(user.otp_auth_secret).now
        post "/api/v1/session", params: { email: user.email, password: password, otp_code: code }, as: :json
        expect(response).to have_http_status(:ok)
        expect(json["access_token"]).to be_present
      end
    end

    it "keeps an account that was set to be deleted, as signing in on the web does" do
      user.update_column(:deleted_at, Time.current)
      post "/api/v1/session", params: { email: user.email, password: password }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["deletion_cancelled"]).to be(true)
      expect(user.reload.deleted_at).to be_nil
    end
  end

  describe "POST /api/v1/registration" do
    it "creates the account and signs the app in" do
      expect do
        post "/api/v1/registration", params: { email: "New.Writer@example.com", password: "a-good-password", first_name: "Ada" }, as: :json
      end.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      created = User.find_by(email: "new.writer@example.com")
      expect(created.first_name).to eq("Ada")
      expect(created.valid_password?("a-good-password")).to be(true)

      get "/api/v1/me", headers: bearer(json["access_token"])
      expect(response).to have_http_status(:ok)
    end

    it "says what's wrong with the account" do
      post "/api/v1/registration", params: { email: user.email, password: "short" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("invalid_account")
      expect(json["details"]).to include(a_string_matching(/Email has already been taken/), a_string_matching(/Password is too short/))
    end

    it "takes no new accounts once a closing is announced" do
      allow(SiteClosure).to receive(:current).and_return(double("closure", closed?: false))
      expect do
        post "/api/v1/registration", params: { email: "late@example.com", password: "a-good-password" }, as: :json
      end.not_to change(User, :count)
      expect(response).to have_http_status(:forbidden)
      expect(json["error"]).to eq("signups_closed")
    end
  end

  describe "/api/v1/account_deletion" do
    let(:token) { Doorkeeper::AccessToken.create!(application: mobile_app, resource_owner_id: user.id, scopes: MobileApp::SCOPE) }
    let(:headers) { bearer(token.plaintext_token) }

    it "says how many entries go with it and what billing to cancel separately" do
      user.update!(plan: "PRO Gumroad Monthly")
      create(:entry, user: user)

      get "/api/v1/account_deletion", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json["entry_count"]).to eq(1)
      expect(json["separate_billing"]).to eq("provider" => "Gumroad", "certain" => true)
    end

    it "has no separate billing for a Stripe customer (the deletion cancels it)" do
      user.update!(plan: "PRO Monthly PayHere", stripe_id: "cus_123")
      get "/api/v1/account_deletion", headers: headers
      expect(json["separate_billing"]).to be_nil
    end

    it "refuses a wrong password and leaves the account alone" do
      post "/api/v1/account_deletion", params: { password: "nope-nope" }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(json["error"]).to eq("incorrect_password")
      expect(user.reload.deleted_at).to be_nil
    end

    it "schedules the deletion for an hour later and signs the app out" do
      freeze_time do
        expect do
          post "/api/v1/account_deletion", params: { password: password }, headers: headers, as: :json
        end.to have_enqueued_job(DeleteUserJob).with(user.id).at(1.hour.from_now)

        expect(response).to have_http_status(:ok)
        expect(json["deletes_at"]).to eq(1.hour.from_now.iso8601)
        expect(user.reload.deleted_at).to eq(Time.current)
      end

      get "/api/v1/me", headers: headers
      expect(response).to have_http_status(:unauthorized)
    end

    it "needs an app token" do
      post "/api/v1/account_deletion", params: { password: password }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.deleted_at).to be_nil
    end
  end
end
