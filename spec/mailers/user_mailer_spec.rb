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

  describe "#no_user_here" do
    let(:notification) { { "email" => "buyer@example.com", "purchaser_id" => "4444" } }

    it "says why the payment wasn't recorded, which account matched, and what to do" do
      email = described_class.no_user_here(notification, provider: "Gumroad", reason: "Because of a test.", user_id: user.id)
      body = email.body.decoded

      expect(email.to).to eq(["hello@#{ENV['MAIN_DOMAIN']}"])
      expect(email.subject).to eq("[REFUND REQUIRED] Payment Without a User")
      expect(body).to include("A Gumroad notification wasn't recorded.", "Why: Because of a test.")
      expect(body).to include("Matched account: mcp-test@example.com (user #{user.id}, #{user.plan})", "/admin/users?email=mcp-test%40example.com")
      expect(body).to include("refund it in Gumroad", "/admin/payments/new")
      expect(body).to include("purchaser_id: '4444'")
    end

    it "still sends the notification when called without a reason" do
      body = described_class.no_user_here(notification).body.decoded

      expect(body).to include("Why: No account matched this payment.", "refund it in the payment provider", "buyer@example.com")
      expect(body).not_to include("Matched account")
    end
  end

  describe "#welcome_email" do
    it "links to settings with a token instead of the posting address" do
      email = described_class.welcome_email(user)
      body = email.html_part.body.decoded + email.text_part.body.decoded

      expect(body).to include("settings?token=")
      expect(body).not_to include("/settings/#{user.user_key}")
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

  describe "#oauth_app_connected" do
    it "names the app and links to Connected apps" do
      email = described_class.oauth_app_connected(user, "Claude", redirect_host: "claude.ai", verified: true)
      body = email.html_part.body.decoded + email.text_part.body.decoded

      expect(email.to).to eq([user.email])
      expect(email.subject).to eq("New app connected to your Dabble Me account")
      expect(body).to include("Claude", "claude.ai", "/security#connected-apps")
      expect(body).not_to include("unverified")
    end

    it "flags unverified apps" do
      email = described_class.oauth_app_connected(user, "Claude", redirect_host: "attacker.example")

      expect(email.text_part.body.decoded).to include("attacker.example (unverified app)")
    end
  end
end
