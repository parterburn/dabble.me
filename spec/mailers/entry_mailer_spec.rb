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
      allow(user).to receive(:days_since_last_post).and_return(1)
    end

    def deliver(entry, on: send_day)
      allow(user).to receive(:random_entry).and_return(entry)
      email = described_class.send_entry(user, nil, send_day: on)
      [email.html_part.body.decoded, email.text_part.body.decoded]
    end

    it "says how many entries they've written this year, counting up to the email's day" do
      [Date.new(2026, 1, 1), Date.new(2026, 6, 15), Date.new(2026, 11, 8)].each { |date| create(:entry, user: user, date: date) }
      create(:entry, user: user, date: Date.new(2026, 11, 20)) # dated after the email

      html, text = deliver(remembered)

      expect(html).to include("You've written 3 entries in 2026.")
      expect(text).to include("You've written 3 entries in 2026.")
      expect(html + text).not_to include("streak")
    end

    it "says 'entry' for one" do
      create(:entry, user: user, date: Date.new(2026, 3, 2))

      expect(deliver(remembered).last).to include("You've written 1 entry in 2026.")
    end

    it "leaves the count out in January" do
      create(:entry, user: user, date: Date.new(2026, 1, 3))
      html, text = deliver(remembered, on: Time.find_zone(user.send_timezone).local(2026, 1, 31, 8))

      expect(html + text).not_to include("You've written")
      expect(text).to include("Reply to this email with your entry for January 31.\n")
    end

    it "starts the count on February 1" do
      create(:entry, user: user, date: Date.new(2026, 1, 3))

      expect(deliver(remembered, on: Time.find_zone(user.send_timezone).local(2026, 2, 1, 8)).last).to include("You've written 1 entry in 2026.")
    end

    it "leaves the count out when they haven't written yet this year" do
      html, text = deliver(remembered) # past_entries are all in 2025

      expect(html + text).not_to include("You've written")
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

    it "tells a newer writer they'll rewind to past entries once they have a few" do
      Entry.where(user: user).where.not(id: past_entries.first(2).map(&:id)).delete_all
      html, text = deliver(nil)

      expect(html).to include("<b>Keep writing...once you have a few entries, you'll rewind to one of them here!</b>")
      expect(text).to include("Keep writing...once you have a few entries, you'll rewind to one of them here!")
      expect(html + text).not_to match(/blast from the past/i)
    end
  end
end
