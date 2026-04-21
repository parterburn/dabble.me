require "rails_helper"

RSpec.describe UserMailer do
  let(:user) { create(:user, email: "mcp-test@example.com", first_name: "Ada") }

  describe "#mcp_access_enabled" do
    it "sends a security notice to the user" do
      email = described_class.mcp_access_enabled(user)

      expect(email.to).to eq([user.email])
      expect(email.subject).to include("MCP access enabled")
      expect(email.body.encoded).to include("Read-only MCP")
      expect(email.body.encoded).to include("access_token")
      expect(email.body.encoded).to include("six months")
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
