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

  describe ".faq_plain_text" do
    it "strips tags, keeps list items apart and decodes entities" do
      html = "<span>Don&#39;t worry.</span><ul><li>One</li><li>Two</li></ul><div>Done</div>"
      expect(ApplicationHelper.faq_plain_text(html)).to eq("Don't worry. One Two Done")
    end
  end
end
