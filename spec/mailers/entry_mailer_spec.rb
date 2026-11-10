require "rails_helper"

RSpec.describe EntryMailer do
  describe "#send_entry" do
    let(:user) { create(:user, send_timezone: "Mountain Time (US & Canada)") }
    let(:send_day) { Time.find_zone(user.send_timezone).local(2026, 11, 8, 8) }
    let!(:past_entries) do
      (1..6).map { |n| create(:entry, user: user, date: Date.new(2025, 11, n + 1), body: "Entry #{n}") }
    end
    let(:remembered) { past_entries.last } # Nov 7, 2025

    before do
      allow(user).to receive(:writing_streak).and_return(2)
      allow(user).to receive(:days_since_last_post).and_return(1)
    end

    def deliver(entry)
      allow(user).to receive(:random_entry).and_return(entry)
      email = described_class.send_entry(user, nil, send_day: send_day)
      [email.html_part.body.decoded, email.text_part.body.decoded]
    end

    it "shows the writing streak with a hyphen and a period" do
      html, text = deliver(remembered)

      expect(html).to include("You're on a 2-day writing streak.")
      expect(text).to include("You're on a 2-day writing streak.")
      expect(html + text).not_to include("day writing streak!")
    end

    it "introduces an entry from this day in an earlier year, bold, with the date linked" do
      on_this_day = create(:entry, user: user, date: Date.new(2025, 11, 8), body: "Limelight Hotel")
      html, text = deliver(on_this_day)

      link = %r{<a class="hover-line" href="[^"]*/entries/2025/11/8">Sat, Nov 8, 2025</a>}
      expect(html).to match(%r{<b>\s*On this day 1 year ago • #{link.source} you wrote\.\.\.\s*</b>})
      expect(text).to include("On this day 1 year ago • Sat, Nov 8, 2025 you wrote...")
      expect(html + text).not_to include("Remember this?")
    end

    it "rewinds to any other day" do
      html, text = deliver(remembered)

      expect(html).to include("Rewind 1 year • <a")
      expect(html).to include(">Fri, Nov 7, 2025</a> you wrote...")
      expect(text).to include("Rewind 1 year • Fri, Nov 7, 2025 you wrote...")
    end
  end
end
