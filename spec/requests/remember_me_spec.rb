# frozen_string_literal: true

require "rails_helper"

# "Stay logged in" is ticked by default: ticked sign-ins also get Devise's
# 30-day remember cookie; unticked ones get a browser-session cookie only.
RSpec.describe "Stay logged in (remember me)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "correct-horse-battery" }
  let(:user) { create(:user, password: password) }

  # The remember cookie is `secure`, so Rails only writes it on HTTPS requests.
  before { https! }

  def set_cookie_header
    Array(response.headers["Set-Cookie"]).join("\n")
  end

  def remember_cookie_set?
    set_cookie_header.match?(/^remember_user_token=[^;]+;/)
  end

  def remember_cookie_expires_at
    line = set_cookie_header.lines.find { |l| l.start_with?("remember_user_token=") }
    Time.httpdate(line[/expires=([^;]+)/i, 1])
  end

  def sign_in_with_password(remember)
    post user_session_path, params: { user: { email: user.email, password: password, remember_me: remember } }
  end

  def remember_checkbox
    response.body[/<input[^>]*type="checkbox"[^>]*name="user\[remember_me\]"[^>]*>/]
  end

  it "ticks the checkbox by default on the sign-in page" do
    get new_user_session_path

    expect(remember_checkbox).to include('checked="checked"')
    expect(response.body).to include("Stay logged in<")
  end

  it "keeps the checkbox unticked after a failed sign-in that unticked it" do
    post user_session_path, params: { user: { email: user.email, password: "wrong-password", remember_me: "0" } }

    expect(remember_checkbox).to be_present
    expect(remember_checkbox).not_to include("checked")
  end

  it "remembers a password sign-in for 30 days when the box is ticked" do
    sign_in_with_password("1")

    expect(response).to have_http_status(:found)
    expect(remember_cookie_set?).to be(true)
    expect(remember_cookie_expires_at).to be_within(1.minute).of(30.days.from_now)
  end

  it "renews the 30 days when the remember cookie signs you back in" do
    sign_in_with_password("1")
    # Simulate a browser restart: the session cookie is gone, the remember cookie stays.
    cookies.delete("_dabbleme_session")

    travel 10.days do
      get entries_path
      expect(response.location.to_s).not_to include("sign_in") # signed back in, not bounced to login
      expect(remember_cookie_expires_at).to be_within(1.minute).of(30.days.from_now)
    end
  end

  it "does not remember a password sign-in when the box is unticked" do
    sign_in_with_password("0")

    expect(response).to have_http_status(:found)
    expect(remember_cookie_set?).to be(false)
  end

  it "keeps the session cookie to the browser session" do
    sign_in_with_password("0")

    session_cookie = set_cookie_header.lines.find { |line| line.start_with?("_dabbleme_session=") }
    expect(session_cookie).to be_present
    expect(session_cookie).not_to match(/expires=/i)
  end

  it "does not remember a new sign-up (the sign-up form has no checkbox)" do
    post user_registration_path, params: {
      user: { email: "new-#{SecureRandom.hex(4)}@example.com", password: password, password_confirmation: password }
    }

    expect(response).to have_http_status(:found)
    expect(remember_cookie_set?).to be(false)
  end

  context "with two-factor authentication" do
    before do
      user.generate_otp_secret
      user.update!(otp_enabled: true, otp_enabled_on: Time.current)
    end

    def complete_otp_challenge
      challenge = user.reload.otp_session_challenge
      remember = Rack::Utils.parse_query(URI(response.headers["Location"]).query)["remember_me"]
      put user_otp_credential_path, params: {
        challenge: challenge, recovery: "false", remember_me: remember,
        token: ROTP::TOTP.new(user.otp_auth_secret).now
      }
    end

    it "remembers when the box was ticked" do
      sign_in_with_password("1")
      complete_otp_challenge

      expect(response).to redirect_to(root_path)
      expect(remember_cookie_set?).to be(true)
    end

    it "does not remember when the box was unticked" do
      sign_in_with_password("0")
      complete_otp_challenge

      expect(response).to redirect_to(root_path)
      expect(remember_cookie_set?).to be(false)
    end
  end

  context "with a passkey" do
    before { register_passkey(user) }

    def sign_in_with_passkey(extra_params)
      get new_passkeys_session_path, as: :json
      assertion = passkey_assertion(challenge: JSON.parse(response.body)["challenge"], user_handle: user.id.to_s)
      post passkeys_sessions_path, params: assertion.merge(extra_params), as: :json
    end

    it "honors an unticked box on the sign-in page" do
      sign_in_with_passkey(remember_me: false)

      expect(response).to have_http_status(:ok)
      expect(remember_cookie_set?).to be(false)
    end

    it "remembers only when the box is ticked" do
      sign_in_with_passkey(remember_me: true)
      expect(remember_cookie_set?).to be(true)

      delete destroy_user_session_path
      sign_in_with_passkey({})
      expect(remember_cookie_set?).to be(false)
    end
  end
end
