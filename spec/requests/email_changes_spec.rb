# frozen_string_literal: true

require "rails_helper"

# Changing the email on Account Security: the new address waits in users.pending_email until a
# code sent there is entered (EmailChangesController). Proving the inbox keeps the account
# verified, so its next code sign-in (EmailSignIn) leaves its password, passkeys and 2FA alone.
RSpec.describe "Changing the account email", type: :request do
  include ActiveJob::TestHelper

  around { |example| perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { example.run } }

  let!(:mobile_app) { MobileApp.ensure_application! }
  let(:password) { "correct-horse-battery" }
  let!(:user) { create(:user, email: "writer@example.com", password: password) }
  let(:new_email) { "new-home@example.com" }

  before do
    ActionMailer::Base.deliveries.clear
    stub_const("EmailSignIn::UNCLAIMED_FROM", 1.year.from_now)
    user.update_column(:email_verified_at, 1.day.ago)
    sign_in user
  end

  def code_sent_to(address)
    mail = ActionMailer::Base.deliveries.reverse.find { |m| m.to.include?(address) && m.subject.to_s.match?(/\A\d{6} /) }
    mail&.subject&.[](/\A\d{6}/)
  end

  def ask_for(email, current_password: password)
    put user_registration_path, params: { user: { email: email, current_password: current_password } }
  end

  def app_code_sign_in(email)
    post "/api/v1/session/code", params: { email: email }, as: :json
    post "/api/v1/session/code/verify", params: { email: email, code: code_sent_to(email) }, as: :json
  end

  it "holds the new address and emails a code there, not to the current one" do
    ask_for(new_email)

    expect(response).to redirect_to(email_change_path)
    user.reload
    expect(user.email).to eq("writer@example.com")
    expect(user.pending_email).to eq(new_email)
    expect(user.email_verified_at).to be_present
    expect(code_sent_to(new_email)).to be_present
    expect(code_sent_to("writer@example.com")).to be_nil

    get email_change_path
    expect(response.body).to include(new_email)
  end

  it "moves the account once the code is entered, keeps it verified, and tells the old address" do
    ask_for(new_email)
    post email_change_path, params: { code: code_sent_to(new_email) }

    expect(response).to redirect_to(security_path)
    user.reload
    expect(user.email).to eq(new_email)
    expect(user.pending_email).to be_nil
    expect(user.email_verified_at).to be_present
    expect(EmailSignIn.unclaimed?(user)).to be(false)
    expect(ActionMailer::Base.deliveries.map(&:to)).to include(["writer@example.com"])
  end

  it "leaves the password alone at the next code sign-in to the new address" do
    ask_for(new_email)
    post email_change_path, params: { code: code_sent_to(new_email) }
    old_key = user.reload.user_key

    app_code_sign_in(new_email)

    expect(response).to have_http_status(:ok)
    user.reload
    expect(user.valid_password?(password)).to be(true)
    expect(user.user_key).to eq(old_key)
  end

  it "doesn't send a victim-bound code to an inbox swapped in before the mail job runs" do
    queued = nil
    allow(UserMailer).to receive(:new_email_code).and_wrap_original do |original, *args|
      queued = args
      original.call(*args)
    end
    ask_for("victim@example.com")
    user.reload.update_column(:pending_email, "attacker@example.com")

    # The mail job loads the user again when it runs, so build the mail from a fresh copy.
    _, code, address = queued
    mail = UserMailer.new_email_code(User.find(user.id), code, address)
    expect(mail.to).to eq(["victim@example.com"])
  end

  it "caps new-address codes per account, even across different addresses" do
    EmailCode::SENDS_PER_HOUR.times { |i| ask_for("rotate-#{i}@example.com") }
    ask_for("one-more@example.com")

    expect(code_sent_to("one-more@example.com")).to be_nil
    expect(flash[:alert]).to include("Too many codes")
  end

  it "stays on the old address after a wrong code" do
    ask_for(new_email)
    post email_change_path, params: { code: "000000" }

    expect(response).to redirect_to(email_change_path)
    expect(user.reload.email).to eq("writer@example.com")
    expect(user.pending_email).to eq(new_email)
  end

  it "doesn't take a code sent to the current address" do
    put user_registration_path, params: { user: { email: new_email, current_password: password } }
    EmailCode.send_confirmation(user.reload)
    post email_change_path, params: { code: code_sent_to("writer@example.com") }

    expect(user.reload.email).to eq("writer@example.com")
  end

  it "needs the current password before a code goes out" do
    ask_for(new_email, current_password: "wrong")

    expect(user.reload.pending_email).to be_nil
    expect(code_sent_to(new_email)).to be_nil
  end

  it "turns away an address another account has" do
    create(:user, email: new_email)
    ask_for(new_email)

    expect(user.reload.pending_email).to be_nil
    expect(code_sent_to(new_email)).to be_nil
  end

  it "keeps the current address when the change is cancelled" do
    ask_for(new_email)
    delete email_change_path

    expect(user.reload.pending_email).to be_nil
    post email_change_path, params: { code: code_sent_to(new_email) }
    expect(user.reload.email).to eq("writer@example.com")
  end

  it "doesn't let a squatter keep an account by moving it onto someone else's inbox" do
    # Verified at their own address, they ask to move to the victim's. The code goes to the
    # victim, so the move never happens, and the victim's own sign-up makes a separate account.
    ask_for("victim@example.com")
    expect(user.reload.email).to eq("writer@example.com")

    app_code_sign_in("victim@example.com")
    expect(response).to have_http_status(:created)
    expect(User.find_by(email: "victim@example.com")).not_to eq(user)
  end

  it "still treats an account moved some other way (an admin edit) as unclaimed" do
    user.update!(email: "moved@example.com")

    expect(user.reload.email_verified_at).to be_nil
    expect(EmailSignIn.unclaimed?(user)).to be(true)
  end

  describe "an account with no password" do
    let!(:user) { create(:user, email: "writer@example.com", password: password).tap { |u| u.update_column(:encrypted_password, "") } }

    it "confirms with a code to the current address, then one to the new address" do
      EmailCode.send_confirmation(user)
      put user_registration_path, params: { user: { email: new_email, email_code: code_sent_to("writer@example.com") } }
      expect(response).to redirect_to(email_change_path)

      post email_change_path, params: { code: code_sent_to(new_email) }
      expect(user.reload.email).to eq(new_email)
      expect(user.email_verified_at).to be_present
    end
  end
end
