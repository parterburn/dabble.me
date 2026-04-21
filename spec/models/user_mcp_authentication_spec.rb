require "rails_helper"

RSpec.describe User, "MCP token authentication" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, plan: "PRO Monthly PayHere").tap do |record|
      record.generate_otp_secret
      record.update!(otp_enabled: true, otp_enabled_on: Time.current)
    end
  end

  describe ".authenticate_mcp_token" do
    it "returns the user when the token is valid and not expired" do
      raw = user.generate_mcp_token!

      found = described_class.authenticate_mcp_token(raw)

      expect(found).to eq(user)
    end

    it "revokes MCP and returns nil when the token has expired" do
      raw = travel_to(Time.zone.local(2025, 1, 1, 12, 0, 0)) { user.generate_mcp_token! }

      travel_to(Time.zone.local(2025, 8, 1, 12, 0, 0)) do
        expect(described_class.authenticate_mcp_token(raw)).to be_nil
      end

      user.reload
      expect(user.mcp_enabled).to eq(false)
      expect(user.mcp_token_digest).to be_blank
    end
  end

  describe "#mcp_available?" do
    it "is false when the token is past expiry" do
      travel_to(Time.zone.local(2025, 1, 1, 12, 0, 0)) { user.generate_mcp_token! }

      travel_to(Time.zone.local(2025, 8, 1, 12, 0, 0)) do
        expect(user.reload.mcp_available?).to eq(false)
      end
    end
  end
end
