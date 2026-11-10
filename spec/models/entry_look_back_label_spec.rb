require "rails_helper"

RSpec.describe Entry, "#look_back_label" do
  let(:send_day) { Time.find_zone("Mountain Time (US & Canada)").local(2026, 11, 8, 20) }

  def label(date)
    Entry.new(date: date).look_back_label(send_day)
  end

  it "says 'On this day' for the same calendar day in an earlier year" do
    expect(label(Date.new(2025, 11, 8))).to eq("On this day 1 year ago")
    expect(label(Date.new(2021, 11, 8))).to eq("On this day 5 years ago")
  end

  it "counts a leap day four years back as the same day" do
    leap_send_day = Time.find_zone("UTC").local(2028, 2, 29, 9)
    expect(Entry.new(date: Date.new(2024, 2, 29)).look_back_label(leap_send_day)).to eq("On this day 4 years ago")
  end

  it "rewinds by whole days under 60 days" do
    expect(label(Date.new(2026, 11, 7))).to eq("Rewind 1 day")
    expect(label(Date.new(2026, 11, 1))).to eq("Rewind 7 days")
    expect(label(Date.new(2026, 10, 8))).to eq("Rewind 31 days")
  end

  it "rewinds by months and years beyond that" do
    expect(label(Date.new(2026, 7, 31))).to eq("Rewind 3 months and 1 week")
    expect(label(Date.new(2024, 8, 3))).to eq("Rewind 2 years and 3 months")
  end

  it "uses the send day in the user's time zone, not UTC" do
    # 8pm Mountain on Nov 8 is already Nov 9 in UTC.
    expect(send_day.utc.to_date).to eq(Date.new(2026, 11, 9))
    expect(label(Date.new(2025, 11, 8))).to eq("On this day 1 year ago")
  end

  it "falls back to a neutral label for a same-day or future entry" do
    expect(label(Date.new(2026, 11, 8))).to eq("From your journal")
    expect(label(Date.new(2026, 12, 1))).to eq("From your journal")
  end
end
