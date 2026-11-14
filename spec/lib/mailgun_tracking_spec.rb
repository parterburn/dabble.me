# frozen_string_literal: true

require "rails_helper"

RSpec.describe MailgunTracking do
  let(:user) { create(:user, email: "tracking-test@example.com", first_name: "Ada") }

  it "turns click and open tracking off for an ordinary email as it's sent, keeping its tag" do
    email = UserMailer.welcome_email(user)
    email.deliver_now

    expect(email.mailgun_options).to include(tag: "Welcome", tracking: "no", "tracking-clicks": "no", "tracking-opens": "no")
  end

  it "covers Devise's emails too" do
    email = Devise::Mailer.reset_password_instructions(user, "token")
    email.deliver_now

    expect(email.mailgun_options).to include(tracking: "no")
  end

  it "leaves an email that asks for tracking alone" do
    message = Mail::Message.new
    message.mailgun_options = { tag: "Newsletter test", tracking: "yes" }
    described_class.delivering_email(message)

    expect(message.mailgun_options).to eq(tag: "Newsletter test", tracking: "yes")
  end
end
