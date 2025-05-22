require 'rails_helper'

describe EmailProcessor do
  include_context 'has all objects'

  describe "#process" do
    it "creates an entry based on the email token" do
      user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "I am great"
      )

      EmailProcessor.new(email).process
      expect(user.entries.reload.first.body).to eq("<div>I am great</div>")
    end

    it "creates an entry from email if the token is wrong but email matches a user" do
      user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        from: ({ email: user.email }),
        to: [{ token: "WRONG", host: ENV['SMTP_DOMAIN'], email: "WRONG@#{ENV['SMTP_DOMAIN']}"}],
        body: "I am great"
      )

      EmailProcessor.new(email).process
      expect(user.entries.reload.first.body).to eq("<div>I am great</div>")
    end

    it "creates an more complex entry based on the email token for free user" do
      user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "I am great\n\nHere's a link: <a href=\"https://www.google.com\" target=\"_blank\">https://www.google.com</a>"
      )

      EmailProcessor.new(email).process
      expect(user.entries.reload.first.body).to eq("I am great<br><br>Here's a link: https://www.google.com")
    end

    it "creates an more complex HTML entry based on the email token for paid user" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "I am great\n\nHere's a link: https://www.google.com",
        vendor_specific: {
          stripped_html: "<p>I am great</p>\n\n<p>Here's a link: <a href=\"https://www.google.com\">https://www.google.com</a></p>"
        }
      )

      EmailProcessor.new(email).process
      expect(paid_user.entries.reload.first.body).to eq("<p>I am great</p><br><br><p>Here's a link: <a href=\"https://www.google.com\" target=\"_blank\">https://www.google.com</a></p>")
    end
  end
end
