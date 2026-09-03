require "rails_helper"

RSpec.describe BusinessMetrics::MailgunStats do
  describe ".event_total" do
    it "sums nested Mailgun failed totals when failed.total is missing" do
      failed = {
        "temporary" => { "espblock" => 1, "total" => 1 },
        "permanent" => { "bounce" => 2, "suppress-complaint" => 0, "total" => 2 }
      }

      expect(described_class.event_total(failed)).to eq(3)
    end

    it "reads a numeric total for accepted and opened events" do
      expect(described_class.event_total("incoming" => 0, "outgoing" => 10, "total" => 10)).to eq(10)
      expect(described_class.event_total("total" => 4)).to eq(4)
    end

    it "returns 0 for a missing event" do
      expect(described_class.event_total(nil)).to eq(0)
    end
  end

  describe BusinessMetrics::MailgunStats::Result do
    it "computes delivery rate from accepted and failed counts" do
      result = described_class.new(sent: 10, failed: 2, opened: 4, complained: 0)

      expect(result.delivery_rate).to eq(10 / 12.0)
    end
  end
end
