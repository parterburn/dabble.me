# frozen_string_literal: true

require "rails_helper"

# There's no "Stay logged in" box: every web sign-in gets Devise's remember cookie
# (User#remember_me), and a browser stays signed in until it goes 30 days without a visit
# (WebSessions.keep_remembered renews the cookies while it's used).
RSpec.describe "Staying signed in (remember me)", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

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

  def device_cookie_set?
    set_cookie_header.match?(/^#{WebSessions::DEVICE_COOKIE}=[^;]+;/)
  end

  def sign_in_with_password(extra = {})
    post user_session_path, params: { user: { email: user.email, password: password }.merge(extra) }
  end

  def signed_in?
    get entries_path
    !response.location.to_s.include?("sign_in")
  end

  it "has no Stay logged in box on Log in or Sign up" do
    get new_user_session_path
    expect(response.body).not_to include("remember_me")
    expect(response.body).not_to include("Stay logged in")

    get new_user_registration_path
    expect(response.body).not_to include("remember_me")
    expect(response.body).not_to include("Stay logged in")
  end

  it "remembers a password sign-in for 30 days" do
    sign_in_with_password

    expect(response).to have_http_status(:found)
    expect(remember_cookie_set?).to be(true)
    expect(remember_cookie_expires_at).to be_within(1.minute).of(30.days.from_now)
  end

  it "remembers even when an old form still sends remember_me=0" do
    sign_in_with_password(remember_me: "0")

    expect(remember_cookie_set?).to be(true)
  end

  it "remembers a new sign-up" do
    post user_registration_path, params: {
      user: { email: "new-#{SecureRandom.hex(4)}@example.com", password: password, password_confirmation: password }
    }

    expect(response).to have_http_status(:found)
    expect(remember_cookie_set?).to be(true)
  end

  it "renews the 30 days when the remember cookie signs you back in" do
    sign_in_with_password
    # Simulate a browser restart: the session cookie is gone, the remember cookie stays.
    cookies.delete("_dabbleme_session")

    travel 10.days do
      expect(signed_in?).to be(true)
      expect(remember_cookie_expires_at).to be_within(1.minute).of(30.days.from_now)
    end
  end

  it "renews the 30 days for a browser that keeps its session open" do
    sign_in_with_password

    travel 25.days do
      expect(signed_in?).to be(true)
      expect(remember_cookie_expires_at).to be_within(1.minute).of(30.days.from_now)
      expect(device_cookie_set?).to be(true)
    end

    # 50 days after sign-in, 25 after the last visit: a browser restart still finds it remembered.
    travel 50.days do
      cookies.delete("_dabbleme_session")
      expect(signed_in?).to be(true)
    end
  end

  it "renews at most once a day" do
    sign_in_with_password
    travel 2.hours do
      get entries_path
      expect(remember_cookie_set?).to be(false)
    end
  end

  it "gives a browser signed in without the box (before this change) a remember cookie on its next visit" do
    sign_in_with_password
    cookies.delete("remember_user_token")

    get entries_path
    expect(remember_cookie_set?).to be(true)

    cookies.delete("_dabbleme_session")
    expect(signed_in?).to be(true)
  end

  it "sets remember_created_at in SQL, not with a full save, for an account that never had one" do
    sign_in_with_password
    cookies.delete("remember_user_token")
    user.update_columns(remember_created_at: nil, updated_at: 1.day.ago)

    expect { get entries_path }.not_to(change { user.reload.updated_at })
    expect(user.remember_created_at).to be_present
    expect(remember_cookie_set?).to be(true)

    cookies.delete("_dabbleme_session")
    expect(signed_in?).to be(true)
  end

  it "stays signed in after a password change and a browser restart" do
    sign_in_with_password
    put user_registration_path, params: { user: { email: user.email, password: "new-password-123",
                                                  password_confirmation: "new-password-123", current_password: password } }
    expect(user.reload.valid_password?("new-password-123")).to be(true)

    get entries_path # the old cookie has the old salt, so it's rewritten now, not tomorrow
    expect(remember_cookie_set?).to be(true)

    cookies.delete("_dabbleme_session")
    expect(signed_in?).to be(true)
  end

  it "remembers a browser signed in before sessions were tracked on its first visit back" do
    # Signed in under the old code: no session row, no device cookie, no remember cookie.
    allow(WebSessions).to receive(:signed_in)
    sign_in_with_password
    allow(WebSessions).to receive(:signed_in).and_call_original
    cookies.delete("remember_user_token")

    get entries_path
    expect(remember_cookie_set?).to be(true)
    expect(device_cookie_set?).to be(true)

    cookies.delete("_dabbleme_session")
    expect(signed_in?).to be(true)
  end

  it "turns away a copied remember cookie replayed without its device cookie" do
    sign_in_with_password # uses the real WebSessions::TRACKING_STARTED_AT, which is already past
    cookies.delete("_dabbleme_session")
    cookies.delete(WebSessions::DEVICE_COOKIE.to_s)

    expect(signed_in?).to be(false)
  end

  it "doesn't renew on JSON requests" do
    sign_in_with_password
    cookies.delete("remember_user_token")

    get new_passkeys_session_path, as: :json
    expect(remember_cookie_set?).to be(false)
  end

  it "signs a browser out after 30 days without a visit" do
    sign_in_with_password

    travel 31.days do
      # The nightly cleanup drops its row, so even a browser that kept its session cookie is out.
      UserSessionCleanupWorker.new.perform
      expect(signed_in?).to be(false)
    end
  end

  context "with two-factor authentication" do
    before do
      user.generate_otp_secret
      user.update!(otp_enabled: true, otp_enabled_on: Time.current)
    end

    it "remembers once the code is in" do
      sign_in_with_password
      put user_otp_credential_path, params: {
        challenge: user.reload.otp_session_challenge, recovery: "false",
        token: ROTP::TOTP.new(user.otp_auth_secret).now
      }

      expect(response).to redirect_to(root_path)
      expect(remember_cookie_set?).to be(true)
    end

    it "remembers an emailed-code sign-in once the code is in" do
      ActionMailer::Base.deliveries.clear
      stub_const("EmailSignIn::UNCLAIMED_FROM", 1.year.from_now)
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { post email_codes_path, params: { user: { email: user.email } } }
      code = ActionMailer::Base.deliveries.last.subject[/\A\d{6}/]
      post verify_email_code_path, params: { code: code }
      expect(response.location).to include(user_otp_credential_path)

      put user_otp_credential_path, params: {
        challenge: user.reload.otp_session_challenge, recovery: "false",
        token: ROTP::TOTP.new(user.otp_auth_secret).now
      }

      expect(response).to redirect_to(root_path)
      expect(remember_cookie_set?).to be(true)
    end
  end

  context "with a passkey" do
    before { register_passkey(user) }

    it "remembers a passkey sign-in" do
      get new_passkeys_session_path, as: :json
      assertion = passkey_assertion(challenge: JSON.parse(response.body)["challenge"], user_handle: user.id.to_s)
      post passkeys_sessions_path, params: assertion, as: :json

      expect(response).to have_http_status(:ok)
      expect(remember_cookie_set?).to be(true)
    end
  end
end
