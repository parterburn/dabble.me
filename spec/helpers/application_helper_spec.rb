require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe ".years_running" do
    it "counts whole years since the September 29, 2014 launch" do
      expect(ApplicationHelper.years_running(Date.new(2026, 9, 28))).to eq(11)
      expect(ApplicationHelper.years_running(Date.new(2026, 9, 29))).to eq(12)
      expect(ApplicationHelper.years_running(Date.new(2027, 9, 28))).to eq(12)
      expect(ApplicationHelper.years_running(Date.new(2027, 9, 29))).to eq(13)
    end
  end
end
