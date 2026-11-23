# frozen_string_literal: true

require "rails_helper"

# Asking to delete the account schedules DeleteUserJob an hour out; signing back in before then
# keeps the account. One Warden hook (config/initializers/devise.rb) does that for every web
# sign-in, so each way in is covered here. The iOS app's API sign-ins clear it themselves
# (spec/requests/api_v1_auth_spec.rb, email_code_sign_in_spec.rb).
RSpec.describe "Signing back in cancels a scheduled account deletion", type: :request do
  include ActiveJob::TestHelper

  around { |example| perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { example.run } }

  let(:password) { "correct-horse-battery" }
  let!(:user) { create(:user, email: "leaving@example.com", password: password) }

  before do
    ActionMailer::Base.deliveries.clear
    stub_const("EmailSignIn::UNCLAIMED_FROM", 1.year.from_now)
    user.update_column(:deleted_at, 10.minutes.ago)
  end

  def deletion_still_runs?
    DeleteUserJob.perform_now(user.id, user.reload.deleted_at.to_i) if user.reload.deleted_at
    User.exists?(user.id)
  end

  def expect_kept
    expect(user.reload.deleted_at).to be_nil
    expect(deletion_still_runs?).to be(true)
  end

  def expect_still_scheduled
    expect(user.reload.deleted_at).to be_present
  end

  def last_code
    ActionMailer::Base.deliveries.last.body.encoded[/\b(\d{6})\b/, 1]
  end

  def turn_on_2fa
    user.generate_otp_secret
    user.update!(otp_enabled: true, otp_enabled_on: 1.day.ago)
  end

  def otp_now
    ROTP::TOTP.new(user.reload.otp_auth_secret).now
  end

  def challenge_from(location)
    Rack::Utils.parse_query(URI(location).query)["challenge"]
  end

  def finish_2fa(token = otp_now)
    put user_otp_credential_path, params: { challenge: challenge_from(response.location), token: token }
  end

  def sign_in_with_code
    post email_codes_path, params: { user: { email: user.email } }
    post verify_email_code_path, params: { code: last_code }
  end

  it "with a password" do
    post user_session_path, params: { user: { email: user.email, password: password } }
    expect_kept
    expect(flash[:notice]).to eq(I18n.t("devise.sessions.deletion_cancelled"))
  end

  it "with an emailed code" do
    sign_in_with_code
    expect(response).to have_http_status(:found)
    expect_kept
    expect(flash[:notice]).to eq(I18n.t("devise.sessions.deletion_cancelled"))
  end

  it "with a passkey" do
    register_passkey(user)
    get new_passkeys_session_path, as: :json
    challenge = JSON.parse(response.body)["challenge"]
    post passkeys_sessions_path, params: passkey_assertion(challenge: challenge, user_handle: user.id.to_s), as: :json
    expect(response).to have_http_status(:ok)
    expect_kept
  end

  describe "with two-factor authentication on" do
    before { turn_on_2fa }

    it "after a password and the authenticator code" do
      post user_session_path, params: { user: { email: user.email, password: password } }
      expect(response.location).to include(user_otp_credential_path)
      expect_still_scheduled # The password alone isn't a sign-in yet.

      finish_2fa
      expect_kept
    end

    it "after an emailed code and the authenticator code" do
      sign_in_with_code
      expect(response.location).to include(user_otp_credential_path)
      expect_still_scheduled

      finish_2fa
      expect_kept
    end

    it "not with a wrong authenticator code" do
      post user_session_path, params: { user: { email: user.email, password: password } }
      finish_2fa("000000")
      expect_still_scheduled
    end
  end

  it "not with a wrong password" do
    post user_session_path, params: { user: { email: user.email, password: "nope-nope-nope" } }
    expect_still_scheduled
  end

  describe "a browser signed in before the deletion was asked for" do
    before do
      https! # The remember cookie is secure.
      user.update_column(:deleted_at, nil)
      post user_session_path, params: { user: { email: user.email, password: password } }
      user.update_column(:deleted_at, 5.minutes.ago)
    end

    it "doesn't cancel it just by loading another page" do
      get entries_path
      expect_still_scheduled
    end

    it "cancels it when the remember cookie signs it back in" do
      cookies.delete("_dabbleme_session")
      get entries_path
      expect_kept
    end
  end
end
