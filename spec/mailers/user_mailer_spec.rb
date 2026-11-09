require "rails_helper"

RSpec.describe UserMailer do
  let(:user) { create(:user, email: "mcp-test@example.com", first_name: "Ada") }

  describe "#posting_address_changed" do
    it "comes from the new posting address and shows it" do
      email = described_class.posting_address_changed(user)
      address = "#{user.user_key}@#{ENV['SMTP_DOMAIN']}"

      expect(email.from).to eq([address])
      expect(email.to).to eq([user.email])
      expect(email.subject).to eq("Your new Dabble Me posting address")
      expect(email.body.encoded).to include(address)
    end
  end

  describe "#passkey_added" do
    it "sends a security notice with the passkey nickname" do
      email = described_class.passkey_added(user, "Work laptop")

      expect(email.to).to eq([user.email])
      expect(email.subject).to include("Passkey added")
      expect(email.body.encoded).to include("Work laptop")
    end
  end
end
