# frozen_string_literal: true

require "rails_helper"

# The Sessions list on Account Security (UserSession, WebSessions, AppSessions) and signing
# devices out: one at a time, or all but this one.
RSpec.describe "Signed-in devices (Sessions on Account Security)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "correct-horse-battery" }
  let(:user) { create(:user, password: password) }
  let(:mobile_app) { MobileApp.ensure_application! }
  let(:mac_safari) do
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"
  end
  let(:place) { { "CF-IPCity" => "Denver", "CF-Region" => "Colorado", "CF-IPCountry" => "US" } }

  # Tracking started yesterday, so a remember cookie written now isn't a legacy one.
  # (Time isn't frozen: Devise takes a remember cookie only if written after remember_created_at.)
  before { stub_const("WebSessions::TRACKING_STARTED_AT", 1.day.ago) }

  before { https! }

  def sign_in_with_password(headers: {})
    post user_session_path, params: { user: { email: user.email, password: password } },
                            headers: { "User-Agent" => mac_safari }.merge(headers)
  end

  # A second browser, with its own cookies.
  def other_browser
    open_session do |browser|
      browser.https!
      browser.post user_session_path, params: { user: { email: user.email, password: password } },
                                      headers: { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0 Safari/537.36" }
    end
  end

  def signed_in?(browser = self)
    browser.get entries_path
    !browser.response.location.to_s.include?("sign_in")
  end

  def app_token(user, application: mobile_app, scopes: MobileApp::SCOPE)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id, scopes: scopes,
                                    use_refresh_token: true, expires_in: 1.day)
  end

  it "lists this browser with where and when it was used, marked This device" do
    sign_in_with_password(headers: place)

    session_row = user.user_sessions.sole
    expect(session_row).to have_attributes(kind: "web", browser: "Safari", os: "Mac", city: "Denver",
                                           region: "Colorado", country: "US")

    get security_path
    expect(response.body).to include("Safari on Mac", "Denver, Colorado, US", "This device", "Active now")
    expect(response.body.index('id="sessions"')).to be < response.body.index("Connected apps")
  end

  it "keeps no IP address" do
    sign_in_with_password
    expect(UserSession.column_names.grep(/ip/)).to be_empty
  end

  it "signs another browser out, along with its remember cookie" do
    browser = other_browser
    sign_in_with_password
    windows = user.user_sessions.find_by!(browser: "Chrome")

    delete signed_in_device_path(windows)
    expect(response).to redirect_to(security_path(anchor: "sessions"))
    expect(UserSession.exists?(windows.id)).to be(false)

    expect(signed_in?(browser)).to be(false)
    # Even after a browser restart: the remember cookie alone doesn't bring it back.
    browser.cookies.delete("_dabbleme_session")
    expect(signed_in?(browser)).to be(false)
    expect(signed_in?).to be(true)
  end

  it "refuses a remember cookie whose device cookie was dropped" do
    sign_in_with_password
    cookies.delete("_dabbleme_session")
    cookies.delete(WebSessions::DEVICE_COOKIE.to_s)

    expect(signed_in?).to be(false)
  end

  it "brings back a remembered browser on its own row" do
    sign_in_with_password
    row = user.user_sessions.sole
    cookies.delete("_dabbleme_session")

    travel 1.hour
    expect(signed_in?).to be(true)
    expect(user.user_sessions.sole).to eq(row)
    expect(row.reload.last_active_at).to be_within(1.second).of(Time.current)
  end

  it "accepts a remember cookie from before sessions were tracked" do
    sign_in_with_password
    stub_const("WebSessions::TRACKING_STARTED_AT", 1.hour.from_now)
    user.user_sessions.delete_all
    cookies.delete("_dabbleme_session")
    cookies.delete(WebSessions::DEVICE_COOKIE.to_s)

    expect(signed_in?).to be(true)
    expect(user.user_sessions.count).to eq(1)
  end

  it "signs only this browser out with Sign Out" do
    browser = other_browser
    sign_in_with_password
    delete destroy_user_session_path

    expect(signed_in?).to be(false)
    expect(user.user_sessions.pluck(:browser)).to eq(["Chrome"])
    browser.cookies.delete("_dabbleme_session")
    expect(signed_in?(browser)).to be(true) # its remember cookie still works
  end

  it "signs this browser out when its own row is signed out" do
    sign_in_with_password
    delete signed_in_device_path(user.user_sessions.sole)

    expect(response).to redirect_to(new_user_session_path)
    expect(signed_in?).to be(false)
  end

  it "doesn't sign out another account's device" do
    sign_in_with_password
    stranger_row = create(:user).user_sessions.create!(kind: "web", last_active_at: Time.current)

    expect { delete signed_in_device_path(stranger_row) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(UserSession.exists?(stranger_row.id)).to be(true)
  end

  describe "Sign out of all other devices" do
    it "ends every other browser, the app and connected apps, and keeps this browser" do
      browser = other_browser
      sign_in_with_password
      app = app_token(user)
      AppSessions.for_token(app, user, ActionDispatch::TestRequest.create)
      claude = Doorkeeper::Application.create!(name: "Claude", redirect_uri: "https://claude.ai/callback",
                                               confidential: false, scopes: "mcp:access")
      mcp = app_token(user, application: claude, scopes: "mcp:access")

      get security_path
      expect(response.body).to include("Sign out of all other devices", "Dabble Me app on iPhone", "disconnect connected apps like Claude")
      delete signed_in_devices_path

      expect(response).to redirect_to(security_path(anchor: "sessions"))
      expect(signed_in?).to be(true)
      expect(user.user_sessions.pluck(:browser)).to eq(["Safari"])
      expect(app.reload).to be_revoked
      expect(mcp.reload).to be_revoked
      expect(flash[:notice]).to include("disconnected your connected apps")
      expect(signed_in?(browser)).to be(false)
    end

    it "keeps this browser remembered" do
      sign_in_with_password
      delete signed_in_devices_path

      cookies.delete("_dabbleme_session")
      expect(signed_in?).to be(true)
    end

    it "also ends browsers signed in before sessions were tracked" do
      sign_in_with_password
      legacy = open_session do |browser|
        browser.https!
        browser.post user_session_path, params: { user: { email: user.email, password: password } }
        browser.cookies.delete(WebSessions::DEVICE_COOKIE.to_s)
      end
      stub_const("WebSessions::TRACKING_STARTED_AT", 1.hour.from_now) # so its cookie is a legacy one
      user.user_sessions.find_by!(browser: "Browser").delete

      delete signed_in_devices_path

      legacy.cookies.delete("_dabbleme_session")
      expect(signed_in?(legacy)).to be(false)
    end
  end

  it "leaves the iOS app out of Connected apps once its sign-ins are under Sessions" do
    sign_in_with_password
    token = app_token(user)

    get security_path
    connected = response.body[response.body.index("Connected apps")..]
    expect(connected).to include(MobileApp::NAME) # not seen since Sessions started: still revocable here

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token.plaintext_token}" }
    expect(token.reload.user_session_id).to be_present

    get security_path
    connected = response.body[response.body.index("Connected apps")..]
    expect(connected).not_to include(MobileApp::NAME)
  end

  it "offers Sign out of all other devices even when this is the only one listed" do
    sign_in_with_password
    get security_path
    expect(response.body).to include("Sign out of all other devices")
  end

  it "drops other browsers and the app when the password changes" do
    browser = other_browser
    sign_in_with_password
    AppSessions.for_token(app_token(user), user, ActionDispatch::TestRequest.create)

    put user_registration_path, params: { user: { password: "new-password-123", password_confirmation: "new-password-123",
                                                  current_password: password } }

    expect(user.user_sessions.pluck(:browser)).to eq(["Safari"])
    expect(signed_in?(browser)).to be(false)
    expect(signed_in?).to be(true)
  end
end
