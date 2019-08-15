require 'rails_helper'
require_relative "../../lib/email_processor"

describe EmailProcessor do
  include_context 'has all objects'

  describe "#process" do
    it "creates an entry based on the email token" do
      email = FactoryBot.build(
        :email,
        to: [{ token: user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "I am great"
      )

      EmailProcessor.new(email).process
      expect(user.entries.first.body).to eq("<p>I am great</p>")
    end

    it "creates an entry from email if the token is wrong but email matches a user" do
      email = FactoryBot.build(
        :email,
        from: ({ email: user.email }),
        to: [{ token: "WRONG", host: ENV['SMTP_DOMAIN'], email: "WRONG@#{ENV['SMTP_DOMAIN']}"}],
        body: "I am great"
      )

      EmailProcessor.new(email).process
      expect(user.entries.first.body).to eq("<p>I am great</p>")
    end
  end
end
