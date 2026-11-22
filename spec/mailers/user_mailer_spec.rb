require "rails_helper"

RSpec.describe UserMailer do
  let(:user) { create(:user, email: "mcp-test@example.com", first_name: "Ada") }

  describe "#export_ready" do
    let(:export) do
      user.exports.create!.tap do |export|
        export.update_columns(status: "ready", storage_key: "exports/x.zip", entry_count: 3, image_count: 0,
                              expires_at: 7.days.from_now)
      end
    end

    it "says to download it before deleting the account" do
      body = described_class.export_ready(export).text_part.body.decoded

      expect(body).to include("If you delete your account, the export is deleted with it")
    end

    it "says the export goes with an account that's being deleted" do
      user.update_column(:deleted_at, Time.current)
      email = described_class.export_ready(export)

      expect(email.text_part.body.decoded).to include("Your account is being deleted, and this export goes with it.")
      expect(email.html_part.body.decoded).to include("Your account is being deleted, and this export goes with it.")
    end
  end

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
    def welcome_text(user)
      email = described_class.welcome_email(user)
      [email.html_part.body.decoded, email.text_part.body.decoded]
    end

    it "asks a web sign-up to reply with their first entry" do
      user.update!(signup_platform: "web")

      welcome_text(user).each do |body|
        expect(body).to include("Just reply to this email with your answer")
        expect(body).not_to include("Open the Dabble Me app")
      end
    end

    it "leads an app sign-up to the app, with replying by email as the aside" do
      user.update!(signup_platform: "ios_app")

      welcome_text(user).each do |body|
        expect(body).to include("Open the Dabble Me app and write a sentence or two")
        expect(body).to include("Settings → Reminders")
        expect(body).to include("Prefer email? Reply to this one")
        expect(body).not_to include("Just reply to this email with your answer")
      end
      text = described_class.welcome_email(user).text_part.body.decoded
      expect(text).to match(/^4\. Turn on a daily reminder/)
      expect(text).to match(/^6\. Unlock premium features/)
    end

    it "links to settings with a token instead of the posting address" do
      email = described_class.welcome_email(user)
      body = email.html_part.body.decoded + email.text_part.body.decoded

      expect(body).to include("settings?token=")
      expect(body).not_to include("/settings/#{user.user_key}")
    end

    it "doesn't send a new (free) account the iOS beta: a TestFlight purchase is free" do
      email = described_class.welcome_email(user)

      expect(email.html_part.body.decoded + email.text_part.body.decoded).not_to include(ApplicationHelper.ios_testflight_url)
    end

    it "gives a new PRO member the iOS beta, in both parts, and never an account that isn't PRO" do
      user.update!(plan: "PRO Monthly PayHere")
      email = described_class.thanks_for_paying(user)

      expect(email.html_part.body.decoded).to include(%(href="#{ApplicationHelper.ios_testflight_url}"))
      expect(email.text_part.body.decoded).to include(ApplicationHelper.ios_testflight_url)

      user.update!(plan: "Free")
      email = described_class.thanks_for_paying(user)
      expect(email.html_part.body.decoded + email.text_part.body.decoded).not_to include(ApplicationHelper.ios_testflight_url)
    end

    it "skips the iPhone app pitch for an Apple plan, which was bought in the app" do
      ["PRO Monthly Apple", "PRO Yearly Apple"].each do |plan|
        user.update!(plan: plan)
        email = described_class.thanks_for_paying(user)
        body = email.html_part.body.decoded + email.text_part.body.decoded

        expect(body).to include("Thanks for subscribing to")
        expect(body).not_to include(ApplicationHelper.ios_testflight_url)
        expect(body).not_to include("On an iPhone or iPad?")
      end
    end
  end

  describe "#entry_not_saved" do
    it "tells the person the entry was not saved, without a journal body" do
      email = described_class.entry_not_saved(user)
      body = email.html_part.body.decoded + email.text_part.body.decoded

      expect(email.to).to eq([user.email])
      expect(email[:from].value).to eq("Dabble Me Support <hello@#{ENV['MAIN_DOMAIN']}>")
      expect(email.subject).to eq("Your Dabble Me entry was not saved")
      expect(body).to include("Hey Ada,", "old posting address", "could not confirm it was sent from your account email", "the entry was not saved")
      expect(body).to include("/settings/posting-address")
      expect(body).not_to match(/spf|dkim/i)
      expect(body).not_to include(user.user_key)
    end
  end

  describe "#failed_entry" do
    it "still goes to support and includes the save error and entry text" do
      email = described_class.failed_entry(user, "Date has already been taken", "2026-11-15", "Today was a good day")

      expect(email.to).to eq(["hello@#{ENV['MAIN_DOMAIN']}"])
      expect(email.subject).to eq("Error saving entry for user #{user.id}")
      expect(email.body.encoded).to include("Date has already been taken", "Today was a good day")
    end
  end

  describe "#passkey_added" do
    it "sends a security notice with the passkey nickname" do
      email = described_class.passkey_added(user, "Work laptop")

      expect(email.to).to eq([user.email])
      expect(email[:from].value).to eq("Dabble Me Support <hello@#{ENV['MAIN_DOMAIN']}>")
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
