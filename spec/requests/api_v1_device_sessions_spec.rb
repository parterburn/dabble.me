# frozen_string_literal: true

require "rails_helper"

# The iOS app's rows in the Sessions list (AppSessions) and Sign Out of All Devices from the app.
RSpec.describe "iOS app sessions (/api/v1/device_sessions)", type: :request do
  let(:user) { create(:user) }
  let(:mobile_app) { MobileApp.ensure_application! }
  let(:place) { { "CF-IPCity" => "Lisbon", "CF-Region" => "Lisbon", "CF-IPCountry" => "PT" } }

  def new_token(user, application: mobile_app, scopes: MobileApp::SCOPE)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id, scopes: scopes,
                                    use_refresh_token: true, expires_in: 1.day)
  end

  def bearer(token, extra = {})
    { "Authorization" => "Bearer #{token.plaintext_token}" }.merge(extra)
  end

  def json
    JSON.parse(response.body)
  end

  it "gives a token a row on its first call, with the device and place, and keeps it" do
    token = new_token(user)
    get "/api/v1/me", headers: bearer(token, "X-Dabble-Device" => "iPad", **place)
    expect(response).to have_http_status(:ok)

    row = user.user_sessions.sole
    expect(row).to have_attributes(kind: "ios_app", os: "iPad", city: "Lisbon", region: "Lisbon", country: "PT",
                                   token_digest: nil)
    expect(token.reload.user_session_id).to eq(row.id)

    get "/api/v1/me", headers: bearer(token)
    expect(user.user_sessions.count).to eq(1)
  end

  it "names an unknown device an iPhone" do
    get "/api/v1/me", headers: bearer(new_token(user), "X-Dabble-Device" => "<script>")
    expect(user.user_sessions.sole.os).to eq("iPhone")
  end

  it "keeps a refreshed token on the same row" do
    post "/api/v1/session", params: { email: user.email, password: user.password }, as: :json
    tokens = json
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{tokens['access_token']}" }
    row = user.user_sessions.sole

    post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: tokens["refresh_token"],
                                   client_id: MobileApp::CLIENT_ID }
    expect(response).to have_http_status(:ok)
    expect(Doorkeeper::AccessToken.order(:id).last.user_session_id).to eq(row.id)

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{json['access_token']}" }
    expect(response).to have_http_status(:ok)
    expect(user.user_sessions.sole).to eq(row)
  end

  it "lists the account's devices, marking this one" do
    user.user_sessions.create!(kind: "web", browser: "Firefox", os: "Linux", last_active_at: 1.day.ago)
    get "/api/v1/device_sessions", headers: bearer(new_token(user), place)

    expect(json["sessions"].map { |s| [s["device"], s["current"]] })
      .to eq([["Dabble Me app on iPhone", true], ["Firefox on Linux", false]])
    expect(json["sessions"].first["location"]).to eq("Lisbon, PT")
  end

  it "turns a token away once its device is signed out on the web" do
    token = new_token(user)
    get "/api/v1/me", headers: bearer(token)
    user.user_sessions.sole.revoke!

    get "/api/v1/me", headers: bearer(token)
    expect(response).to have_http_status(:unauthorized)
    expect(token.reload).to be_revoked
  end

  it "turns away a token whose row is gone even if the token wasn't revoked" do
    token = new_token(user)
    get "/api/v1/me", headers: bearer(token)
    user.user_sessions.delete_all

    get "/api/v1/me", headers: bearer(token)
    expect(response).to have_http_status(:unauthorized)
  end

  it "signs out one device" do
    other = new_token(user)
    get "/api/v1/me", headers: bearer(other)
    other_row = user.user_sessions.sole

    delete "/api/v1/device_sessions/#{other_row.id}", headers: bearer(new_token(user))
    expect(response).to have_http_status(:no_content)
    expect(other.reload).to be_revoked
  end

  it "won't sign out another account's device" do
    stranger_row = create(:user).user_sessions.create!(kind: "web", last_active_at: Time.current)
    delete "/api/v1/device_sessions/#{stranger_row.id}", headers: bearer(new_token(user))

    expect(response).to have_http_status(:not_found)
    expect(UserSession.exists?(stranger_row.id)).to be(true)
  end

  it "signs out of all devices, this app and connected apps included" do
    this_app = new_token(user)
    other_app = new_token(user)
    claude = Doorkeeper::Application.create!(name: "Claude", redirect_uri: "https://claude.ai/callback",
                                             confidential: false, scopes: "mcp:access")
    mcp = new_token(user, application: claude, scopes: "mcp:access")
    user.user_sessions.create!(kind: "web", last_active_at: Time.current)
    salt = user.authenticatable_salt

    delete "/api/v1/device_sessions", headers: bearer(this_app)

    expect(response).to have_http_status(:no_content)
    expect([this_app.reload, other_app.reload]).to all(be_revoked)
    expect(mcp.reload).to be_revoked
    expect(user.user_sessions.count).to eq(0)
    expect(user.reload.authenticatable_salt).not_to eq(salt) # every browser's cookies stop matching

    get "/api/v1/me", headers: bearer(this_app)
    expect(response).to have_http_status(:unauthorized)
  end

  it "doesn't track tokens of other clients" do
    claude = Doorkeeper::Application.create!(name: "Claude", redirect_uri: "https://claude.ai/callback",
                                             confidential: false, scopes: "mcp:access #{MobileApp::SCOPE}")
    get "/api/v1/me", headers: bearer(new_token(user, application: claude))
    expect(user.user_sessions.count).to eq(0)
  end
end
