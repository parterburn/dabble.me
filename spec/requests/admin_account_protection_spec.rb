# frozen_string_literal: true

require "rails_helper"
require "rake"

# AdminAccounts: an admin's passkeys go only from the Rails console, and the console can take
# an admin's password away so they sign in with a passkey or an emailed code.
RSpec.describe "Admin account protection", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "correct-horse-battery" }
  let(:admin) { create(:user, admin: true, password: password) }
  let!(:credential) { register_passkey(admin) }

  def verify_passkey
    get options_passkeys_verification_path, as: :json
    options = JSON.parse(response.body)
    post passkeys_verification_path,
      params: passkey_assertion(challenge: options["challenge"], user_handle: admin.id.to_s),
      as: :json
  end

  describe "the passkey itself" do
    it "won't be destroyed outside the console" do
      expect(credential.destroy).to be(false)
      expect(credential.errors.full_messages.to_sentence).to include("Rails console")
      expect { credential.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(admin.webauthn_credentials.count).to eq(1)
    end

    it "survives destroy_all on the account's passkeys" do
      expect { admin.webauthn_credentials.destroy_all }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(admin.webauthn_credentials.count).to eq(1)
    end

    it "goes inside AdminAccounts.allow_passkey_removal" do
      AdminAccounts.allow_passkey_removal { credential.destroy! }
      expect(admin.webauthn_credentials.count).to eq(0)
      expect(AdminAccounts.passkey_removal_allowed?).to be(false)
    end

    it "keeps the whole account from destroy, before anything it owns goes" do
      entry = create(:entry, user: admin)
      expect(admin.destroy).to be(false)
      expect(Entry.exists?(entry.id)).to be(true)

      AdminAccounts.allow_passkey_removal { admin.destroy! }
      expect(User.exists?(admin.id)).to be(false)
    end

    it "leaves other accounts' passkeys removable" do
      other = create(:webauthn_credential)
      expect(other.destroy).to be_truthy
    end
  end

  describe "on the web" do
    before { sign_in admin }

    it "shows no Remove link or delete-account link to an admin" do
      verify_passkey
      get security_path

      expect(response.body).to include("Admin passkey")
      expect(response.body).not_to include(">Remove<")
      expect(response.body).not_to include(delete_account_path)
    end

    it "refuses to delete an admin's account" do
      verify_passkey
      get delete_account_path
      expect(response).to redirect_to(security_path)

      delete user_registration_path, params: { user: { current_password: password } }
      expect(response).to redirect_to(security_path)
      expect(flash[:alert]).to include("Rails console")
      expect(admin.reload.deleted_at).to be_nil
      expect(enqueued_jobs.map { |job| job["job_class"] }).not_to include("DeleteUserJob")
    end
  end

  describe "in the app" do
    let!(:mobile_app) { MobileApp.ensure_application! }
    let(:headers) { { "Authorization" => "Bearer #{MobileApp.issue_token!(admin).plaintext_token}" } }

    it "refuses to delete an admin's account" do
      post "/api/v1/account_deletion", params: { password: password }, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("admin_account")
      expect(admin.reload.deleted_at).to be_nil
    end

    it "won't add a passkey for an admin (that happens on the web, behind its checks)" do
      post "/api/v1/passkeys/options", params: { current_password: password }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)

      AdminAccounts.allow_passkey_removal { credential.destroy! }
      post "/api/v1/passkeys/options", params: { current_password: password }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(MobileApp.passkey_setup(admin, MobileApp.issue_token!(admin))).to eq({})
    end
  end

  describe "an admin's first passkey on the web" do
    before do
      AdminAccounts.allow_passkey_removal { credential.destroy! }
      sign_in admin
    end

    def add_passkey(**proof)
      get new_passkeys_registration_path, as: :json
      challenge = JSON.parse(response.body)["challenge"]
      attestation = passkey_client.create(challenge: challenge, user_verified: true)
      post passkeys_registrations_path, params: attestation.merge(nickname: "Laptop", **proof), as: :json
    end

    it "takes the password" do
      expect { add_passkey(current_password: password) }.to change { admin.webauthn_credentials.count }.by(1)
    end

    it "won't take an emailed code, or the minutes after a code sign-in (the inbox alone)" do
      code = EmailCode.issue!(admin.email, purpose: "confirm", user: admin)
      expect { add_passkey(email_code: code) }.not_to change { admin.webauthn_credentials.count }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  it "keeps another admin from moving an admin's email" do
    other_admin = create(:user, admin: true)
    register_passkey(other_admin, client: WebAuthn::FakeClient.new(WebAuthn.configuration.allowed_origins.first))
    allow(AdminAccess).to receive(:passkey_fresh?).and_return(true)
    sign_in other_admin

    patch admin_user_path(admin), params: { user: { email: "someone-else@example.com" } }
    expect(admin.reload.email).not_to eq("someone-else@example.com")
  end

  it "stops a deletion queued before the account was made admin" do
    admin.update_column(:deleted_at, Time.current)

    DeleteUserJob.perform_now(admin.id, admin.deleted_at.to_i)

    expect(User.exists?(admin.id)).to be(true)
    expect(admin.reload.deleted_at).to be_nil
    expect(admin.webauthn_credentials.count).to eq(1)
  end

  it "keeps an account made admin while its deletion ran, and clears the deletion" do
    user = create(:user)
    user.update_column(:deleted_at, Time.current)
    allow(user).to receive(:lock!) { user.update_column(:admin, true); user.reload }
    allow(User).to receive(:find_by).and_call_original
    allow(User).to receive(:find_by).with(id: user.id).and_return(user)

    DeleteUserJob.perform_now(user.id, user.deleted_at.to_i)

    expect(User.exists?(user.id)).to be(true)
    expect(user.reload.deleted_at).to be_nil
  end

  describe "an emailed-code sign-in" do
    it "never treats an admin as unclaimed, so nothing is wiped and 2FA still applies" do
      admin.update_columns(email_verified_at: nil, email_changed_at: Time.current)

      expect(EmailSignIn.unclaimed?(admin)).to be(false)
      expect { admin.clear_credentials_for_email_claim! }.to raise_error(AdminAccounts::Refused)
      expect(admin.reload.webauthn_credentials.count).to eq(1)
      expect(admin.valid_password?(password)).to be(true)
    end
  end

  describe "admin:remove_password" do
    before(:all) do
      Rails.application.load_tasks unless Rake::Task.task_defined?("admin:remove_password")
    end

    def run(email)
      task = Rake::Task["admin:remove_password"]
      task.reenable
      task.invoke(email)
    end

    it "removes the password, so a passkey or an emailed code is the way in" do
      old_salt = admin.authenticatable_salt

      expect { run(admin.email.upcase) }.to output(/Removed the password/).to_stdout

      admin.reload
      expect(admin.has_password?).to be(false)
      expect(admin.valid_password?(password)).to be(false)
      expect(admin.authenticatable_salt).not_to eq(old_salt)
      expect(admin.webauthn_credentials.count).to eq(1)
    end

    it "refuses an account that isn't an admin" do
      user = create(:user, password: password)
      expect { run(user.email) }.to raise_error(SystemExit).and output(/isn't an admin/).to_stderr
      expect(user.reload.valid_password?(password)).to be(true)
    end

    it "refuses an admin with no passkey, who would be left with only the inbox" do
      AdminAccounts.allow_passkey_removal { credential.destroy! }
      expect { run(admin.email) }.to raise_error(SystemExit).and output(/no passkey/).to_stderr
      expect(admin.reload.has_password?).to be(true)
    end
  end

  describe "an admin with no password" do
    before { AdminAccounts.remove_password!(admin) }

    it "still signs in with a passkey and reaches the admin pages" do
      get new_passkeys_session_path, as: :json
      challenge = JSON.parse(response.body)["challenge"]
      post passkeys_sessions_path, params: passkey_assertion(challenge: challenge, user_handle: admin.id.to_s), as: :json
      expect(response).to have_http_status(:ok)

      get admin_users_path
      expect(response).to have_http_status(:ok)
    end

    it "can't sign in with the old password" do
      post user_session_path, params: { user: { email: admin.email, password: password } }
      expect(controller.current_user).to be_nil
    end

    it "gets back into the two-factor settings with an emailed code, as it has no password to type" do
      admin.generate_otp_secret
      admin.update!(otp_enabled: true, otp_enabled_on: 1.day.ago)
      sign_in admin
      verify_passkey
      get user_otp_token_path
      expect(response).to have_http_status(:ok)

      travel 20.minutes do
        get user_otp_token_path
        expect(response).to redirect_to(refresh_user_otp_credential_path)

        get refresh_user_otp_credential_path
        expect(response.body).to include("Email me a code")

        put refresh_user_otp_credential_path, params: { user: { email_code: "000000" } }
        expect(response).to have_http_status(:unprocessable_content)

        code = EmailCode.issue!(admin.email, purpose: "confirm", user: admin)
        put refresh_user_otp_credential_path, params: { user: { email_code: code } }
        expect(response).to redirect_to(user_otp_token_path)
      end
    end

    it "confirms Account Security changes with an emailed code" do
      sign_in admin
      verify_passkey
      get security_path
      expect(response.body).to include("set a password")
    end
  end
end
