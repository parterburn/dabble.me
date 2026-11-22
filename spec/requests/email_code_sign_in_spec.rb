# frozen_string_literal: true

require "rails_helper"

# Passwordless sign-in and sign-up by emailed code (EmailSignIn, EmailCode): the iOS app's
# /api/v1/session/code and the web's /users/sign_in/code.
RSpec.describe "Email-code sign-in and sign-up", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  # Deliver the emails (codes, welcome) as they're queued, to read the codes back.
  around { |example| perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { example.run } }

  let!(:mobile_app) { MobileApp.ensure_application! }
  let(:password) { "correct-horse-battery" }
  let!(:user) { create(:user, email: "writer@example.com", password: password) }

  before { ActionMailer::Base.deliveries.clear }

  def json
    JSON.parse(response.body)
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def code_emails
    ActionMailer::Base.deliveries.select { |mail| mail.subject.to_s.match?(/\A\d{6} is your Dabble Me/) }
  end

  def last_code(to: nil)
    mails = code_emails
    mails = mails.select { |mail| mail.to.include?(to) } if to
    mails.last.subject[/\A\d{6}/]
  end

  def send_app_code(email)
    post "/api/v1/session/code", params: { email: email }, as: :json
  end

  def verify_app_code(email, code, otp_code: nil)
    post "/api/v1/session/code/verify", params: { email: email, code: code, otp_code: otp_code }.compact, as: :json
  end

  describe "EmailCode" do
    it "stores only digests: not the code, not the address" do
      code = EmailCode.issue!("someone@example.com", purpose: "sign_in")
      row = EmailCode.last
      expect(row.attributes.values.map(&:to_s).join(" ")).not_to include(code)
      expect(row.attributes.values.map(&:to_s).join(" ")).not_to include("someone@example.com")
    end

    it "works once" do
      code = EmailCode.issue!("someone@example.com", purpose: "sign_in")
      expect(EmailCode.redeem("someone@example.com", code, purpose: "sign_in")).to be(true)
      expect(EmailCode.redeem("someone@example.com", code, purpose: "sign_in")).to be(false)
    end

    it "keeps a sign-in code for sign-in only" do
      code = EmailCode.issue!("someone@example.com", purpose: "sign_in")
      expect(EmailCode.redeem("someone@example.com", code, purpose: "confirm")).to be(false)
      expect(EmailCode.redeem("other@example.com", code, purpose: "sign_in")).to be(false)
    end

    it "runs out after its lifetime" do
      code = EmailCode.issue!("someone@example.com", purpose: "sign_in")
      travel EmailCode::LIFETIME + 1.second do
        expect(EmailCode.redeem("someone@example.com", code, purpose: "sign_in")).to be(false)
      end
    end

    it "stops working after too many wrong guesses" do
      code = EmailCode.issue!("someone@example.com", purpose: "sign_in")
      wrong = code == "000000" ? "111111" : "000000"
      EmailCode::MAX_ATTEMPTS.times { EmailCode.redeem("someone@example.com", wrong, purpose: "sign_in") }
      expect(EmailCode.redeem("someone@example.com", code, purpose: "sign_in")).to be(false)
    end

    it "stops taking guesses for the day, whatever new codes are sent" do
      wrong = "999999"
      (EmailCode::DAILY_FAILURES / EmailCode::MAX_ATTEMPTS).times do |i|
        travel_to(Time.current + (i * 2).minutes) do
          EmailCode.issue!("someone@example.com", purpose: "sign_in")
          EmailCode::MAX_ATTEMPTS.times { EmailCode.redeem("someone@example.com", wrong, purpose: "sign_in") }
        end
      end
      travel 2.hours do
        code = EmailCode.issue!("someone@example.com", purpose: "sign_in")
        expect(EmailCode.redeem("someone@example.com", code, purpose: "sign_in")).to be(false)
      end
    end

    it "keeps the code before a resend working, and voids the rest once one is used" do
      first = EmailCode.issue!("someone@example.com", purpose: "sign_in")
      second = EmailCode.issue!("someone@example.com", purpose: "sign_in")
      expect(EmailCode.redeem("someone@example.com", first, purpose: "sign_in")).to be(true)
      expect(EmailCode.redeem("someone@example.com", second, purpose: "sign_in")).to be(false)
    end

    it "limits how often an address gets a code" do
      EmailCode.issue!("someone@example.com", purpose: "sign_in")
      expect(EmailCode.send_status("someone@example.com", purpose: "sign_in")).to eq(:too_soon)
      travel 1.minute do
        expect(EmailCode.send_status("someone@example.com", purpose: "sign_in")).to eq(:ok)
        (EmailCode::SENDS_PER_HOUR - 1).times { EmailCode.issue!("someone@example.com", purpose: "sign_in") }
      end
      travel 5.minutes do
        expect(EmailCode.send_status("someone@example.com", purpose: "sign_in")).to eq(:too_many)
      end
    end

    it "is cleaned up after a couple of days" do
      EmailCode.issue!("someone@example.com", purpose: "sign_in")
      travel(EmailCode::KEEP_FOR + 1.minute) { EmailCodeCleanupWorker.new.perform }
      expect(EmailCode.count).to eq(0)
    end
  end

  describe "the app (POST /api/v1/session/code)" do
    it "answers the same for an address with an account and one without, and makes no account" do
      send_app_code("Writer@Example.com ")
      known = [response.status, json.except("email")]
      send_app_code("nobody@example.com")
      unknown = [response.status, json.except("email")]

      expect(known).to eq(unknown)
      expect(response).to have_http_status(:accepted)
      expect(json["email"]).to eq("nobody@example.com")
      expect(User.find_by(email: "nobody@example.com")).to be_nil
      expect(code_emails.map(&:to)).to eq([["writer@example.com"], ["nobody@example.com"]])
    end

    it "words the email for a sign-in or a new account" do
      send_app_code(user.email)
      send_app_code("nobody@example.com")
      expect(code_emails.first.text_part.body.to_s).to include("sign in")
      expect(code_emails.last.text_part.body.to_s).to include("create your Dabble Me account")
    end

    it "refuses something that isn't an email" do
      send_app_code("not-an-email")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("invalid_email")
      expect(code_emails).to be_empty
    end

    it "says a code just went out instead of sending another straight away" do
      send_app_code(user.email)
      send_app_code(user.email)
      expect(response).to have_http_status(:too_many_requests)
      expect(json["error"]).to eq("too_soon")
      expect(code_emails.size).to eq(1)
    end
  end

  describe "the app (POST /api/v1/session/code/verify)" do
    it "signs an existing account in, leaving its password alone" do
      send_app_code(user.email)
      verify_app_code(user.email, last_code)

      expect(response).to have_http_status(:ok)
      expect(json).to include("token_type" => "Bearer", "created" => false)
      expect(json["passkey_setup_token"]).to be_present
      expect(Doorkeeper::AccessToken.last.resource_owner_id).to eq(user.id)
      expect(user.reload.valid_password?(password)).to be(true)
      expect(user.email_verified_at).to be_present

      get "/api/v1/me", headers: bearer(json["access_token"])
      expect(JSON.parse(response.body)).to include("email" => user.email, "has_password" => true)
    end

    it "makes the account for a new address only once its code is entered" do
      send_app_code("New.Writer@example.com")
      expect(User.find_by(email: "new.writer@example.com")).to be_nil

      expect { verify_app_code("new.writer@example.com", last_code) }.to change(User, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(json["created"]).to be(true)
      expect(json["access_token"]).to be_present

      created = User.find_by(email: "new.writer@example.com")
      expect(created.has_password?).to be(false)
      expect(created.email_verified_at).to be_present
      expect(created.first_name).to be_nil
      expect(ActionMailer::Base.deliveries.map(&:subject)).to include("Let's write your first Dabble Me entry")

      get "/api/v1/me", headers: bearer(json["access_token"])
      expect(JSON.parse(response.body)["has_password"]).to be(false)
    end

    it "leaves nothing behind for a mistyped address that never gets its code" do
      send_app_code("writer@gmial.com")
      expect(User.find_by(email: "writer@gmial.com")).to be_nil
      expect(EmailCode.count).to eq(1)
    end

    it "refuses a wrong code the same way for any address" do
      send_app_code(user.email)
      verify_app_code(user.email, "000000")
      known = json
      verify_app_code("nobody@example.com", "000000")
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq(known)
      expect(json["error"]).to eq("invalid_code")
      expect(Doorkeeper::AccessToken.count).to eq(0)
    end

    it "refuses a code used once already" do
      send_app_code(user.email)
      code = last_code
      verify_app_code(user.email, code)
      verify_app_code(user.email, code)
      expect(response).to have_http_status(:unauthorized)
    end

    it "makes no account once a closing is announced" do
      SiteClosure.create!(closes_on: SiteClosure.today + 30)
      send_app_code("late@example.com")
      verify_app_code("late@example.com", last_code)
      expect(response).to have_http_status(:forbidden)
      expect(json["error"]).to eq("signups_closed")
      expect(User.find_by(email: "late@example.com")).to be_nil
    end

    context "with two-factor authentication on" do
      before do
        user.generate_otp_secret
        user.update!(otp_enabled: true, otp_enabled_on: Time.current)
      end

      it "asks for the authenticator code after the emailed one, without using the emailed one up" do
        send_app_code(user.email)
        code = last_code
        verify_app_code(user.email, code)
        expect(response).to have_http_status(:unauthorized)
        expect(json["error"]).to eq("otp_required")

        verify_app_code(user.email, code, otp_code: "000000")
        expect(json["error"]).to eq("invalid_otp")

        verify_app_code(user.email, code, otp_code: ROTP::TOTP.new(user.reload.otp_auth_secret).now)
        expect(response).to have_http_status(:ok)
        expect(json["access_token"]).to be_present
      end

      it "lets one emailed code buy only a few authenticator guesses" do
        send_app_code(user.email)
        code = last_code
        EmailCode::MAX_ATTEMPTS.times do
          verify_app_code(user.email, code, otp_code: "000000")
          expect(json["error"]).to eq("invalid_otp")
        end

        verify_app_code(user.email, code, otp_code: ROTP::TOTP.new(user.reload.otp_auth_secret).now)
        expect(json["error"]).to eq("invalid_code")
      end
    end

    it "keeps an account set to be deleted, as a password sign-in does" do
      user.update_column(:deleted_at, Time.current)
      send_app_code(user.email)
      verify_app_code(user.email, last_code)
      expect(json["deletion_cancelled"]).to be(true)
      expect(user.reload.deleted_at).to be_nil
    end
  end

  describe "an account with no password, in the app" do
    let(:passwordless) do
      send_app_code("nopass@example.com")
      verify_app_code("nopass@example.com", last_code)
      User.find_by!(email: "nopass@example.com")
    end
    let(:token) { MobileApp.issue_token!(passwordless).plaintext_token }

    it "can't sign in with a blank or guessed password" do
      passwordless
      post "/api/v1/session", params: { email: "nopass@example.com", password: "" }, as: :json
      expect(json["error"]).to eq("invalid_credentials")
    end

    it "deletes the account with an emailed code in place of the password" do
      post "/api/v1/confirmation_code", headers: bearer(token), as: :json
      expect(response).to have_http_status(:accepted)
      code = ActionMailer::Base.deliveries.last.subject[/\A\d{6}/]

      post "/api/v1/account_deletion", params: { email_code: "000000" }, headers: bearer(token), as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/account_deletion", params: { email_code: code }, headers: bearer(token), as: :json
      expect(response).to have_http_status(:ok)
      expect(passwordless.reload.deleted_at).to be_present
    end

    it "adds a passkey with an emailed code: the options hand back a setup token for the passkey" do
      post "/api/v1/confirmation_code", headers: bearer(token), as: :json
      code = ActionMailer::Base.deliveries.last.subject[/\A\d{6}/]

      post "/api/v1/passkeys/options", params: { email_code: code }, headers: bearer(token), as: :json
      expect(response).to have_http_status(:ok)
      expect(json["setup_token"]).to be_present
      expect(json["challenge_token"]).to be_present

      # Used up: the same code doesn't work twice.
      post "/api/v1/passkeys/options", params: { email_code: code }, headers: bearer(token), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "won't take another account's confirmation code" do
      post "/api/v1/confirmation_code", headers: bearer(token), as: :json
      code = ActionMailer::Base.deliveries.last.subject[/\A\d{6}/]
      other = MobileApp.issue_token!(user).plaintext_token

      post "/api/v1/account_deletion", params: { email_code: code }, headers: bearer(other), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the web" do
    def send_web_code(email, **extra)
      post email_codes_path, params: { user: { email: email, remember_me: "1" } }.merge(extra)
    end

    it "asks only for an email on Log in and Sign up" do
      get new_user_session_path
      expect(response.body).to include('name="user[email]"')
      expect(response.body).to include('autocomplete="username webauthn"')
      expect(response.body).not_to include('name="user[password]"')

      get new_user_registration_path
      expect(response.body).to include('name="user[email]"')
      expect(response.body).not_to include('name="user[password]"')
    end

    it "shows the same code page for an address with an account and one without" do
      send_web_code(user.email)
      expect(response).to redirect_to(email_code_path)
      follow_redirect!
      known = response.body.gsub(user.email, "EMAIL").gsub(CGI.escape(user.email), "EMAIL")

      reset!
      send_web_code("nobody@example.com")
      follow_redirect!
      unknown = response.body.gsub("nobody@example.com", "EMAIL").gsub(CGI.escape("nobody@example.com"), "EMAIL")

      strip = ->(html) { html.gsub(/name="authenticity_token" value="[^"]+"/, "").gsub(/<meta name="csrf-token"[^>]+>/, "") }
      expect(strip.call(unknown)).to eq(strip.call(known))
      expect(response.body).to include("Wrong email?")
      expect(response.body).to include('autocomplete="one-time-code"')
      expect(response.body).to include("Use password instead")
    end

    it "sends no code when the captcha fails" do
      allow_any_instance_of(EmailCodesController).to receive(:valid_captcha?).and_return(false)
      send_web_code(user.email)
      expect(response).to redirect_to(new_user_session_path(email: user.email))
      expect(flash[:alert]).to include("captcha")
      expect(code_emails).to be_empty
    end

    it "signs an existing account in with the code" do
      send_web_code(user.email)
      post verify_email_code_path, params: { code: last_code }
      expect(response).to redirect_to(root_path)
      get edit_user_registration_path
      expect(response).to have_http_status(:ok)
    end

    it "makes a new account with the code, with no password" do
      send_web_code("webnew@example.com")
      expect { post verify_email_code_path, params: { code: last_code } }.to change(User, :count).by(1)
      expect(flash[:notice]).to include("Welcome to Dabble Me")
      expect(User.find_by(email: "webnew@example.com").has_password?).to be(false)
    end

    it "shows a wrong code on the code page" do
      send_web_code(user.email)
      post verify_email_code_path, params: { code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(CGI.unescapeHTML(response.body)).to include("That code didn't work")
    end

    it "sends a wrong password from the code page back to the code page" do
      send_web_code(user.email)
      post user_session_path, params: { user: { email: user.email, password: "nope-nope" }, from_code: "1" }
      expect(response).to redirect_to(email_code_path(password: 1))
    end

    it "still signs in with the password from the code page" do
      send_web_code(user.email)
      post user_session_path, params: { user: { email: user.email, password: password }, from_code: "1" }
      expect(response).to redirect_to(root_path)
    end

    it "asks for the 2FA code after the emailed code" do
      user.generate_otp_secret
      user.update!(otp_enabled: true, otp_enabled_on: Time.current)
      send_web_code(user.email)
      post verify_email_code_path, params: { code: last_code }
      expect(response.location).to include(user_otp_credential_path)
      get edit_user_registration_path
      expect(response).not_to have_http_status(:ok)
    end

    it "puts a gift on an account made from a gift link" do
      allow(Gift).to receive(:codes).and_return({ "friends" => nil }) if Gift.respond_to?(:codes)
      gift = instance_double(Gift, code: "friends")
      allow(Gift).to receive(:find).and_return(nil)
      allow(Gift).to receive(:find).with("friends").and_return(gift)
      allow(gift).to receive(:redeem!).and_return(true)

      send_web_code("gifted@example.com", gift_code: "friends")
      post verify_email_code_path, params: { code: last_code }
      created = User.find_by(email: "gifted@example.com")
      expect(gift).to have_received(:redeem!).with(created)
      expect(ActionMailer::Base.deliveries.map(&:subject)).to include("Let's write your first Dabble Me entry")
    end

    describe "an account with no password" do
      let!(:passwordless) { User.create!(email: "nopass@example.com", passwordless_signup: true) }

      before { sign_in passwordless }

      it "confirms deleting the account with an emailed code" do
        post confirmation_code_path, headers: { "HTTP_REFERER" => delete_account_url }
        code = ActionMailer::Base.deliveries.last.subject[/\A\d{6}/]

        delete user_registration_path, params: { user: { email_code: code } }
        expect(passwordless.reload.deleted_at).to be_present
      end

      it "sets a first password with an emailed code" do
        put confirmation_code_path, headers: { "HTTP_REFERER" => security_url }
        code = ActionMailer::Base.deliveries.last.subject[/\A\d{6}/]

        put user_registration_path, params: { submit_method: "security",
                                              user: { email: passwordless.email, password: "a fine new password",
                                                      password_confirmation: "a fine new password", email_code: code } }
        expect(passwordless.reload.valid_password?("a fine new password")).to be(true)
      end

      it "refuses a change without the code" do
        put user_registration_path, params: { submit_method: "security", user: { email: "moved@example.com", email_code: "000000" } }
        expect(passwordless.reload.email).to eq("nopass@example.com")
      end

      it "shows the code field in place of the password on Account Security" do
        get security_path
        expect(response.body).to include("Email me a code")
        expect(response.body).not_to include("user[current_password]")
      end
    end
  end
end
