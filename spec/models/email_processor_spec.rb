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
      expect(user.entries.reload.first.body).to eq("<p>I am great<br></p>")
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
      expect(user.entries.reload.first.body).to eq("<p>I am great<br></p>")
    end
  end
end
