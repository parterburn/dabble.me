require "rails_helper"
require Rails.root.join("lib/sentry_sensitive_scrubber")

RSpec.describe SentrySensitiveScrubber do
  describe ".scrub_string" do
    it "redacts dmcp bearer tokens" do
      raw = "prefix dmcp_abcXYZ-12_3 suffix"
      expect(described_class.scrub_string(raw)).to eq("prefix #{described_class::FILTERED} suffix")
    end

    it "redacts Bearer header values" do
      expect(described_class.scrub_string('Authorization: Bearer dmcp_xx')).to include(described_class::FILTERED)
    end

    it "redacts access_token query segments" do
      url = "https://example.com/mcp?access_token=dmcp_secret&foo=1"
      expect(described_class.scrub_string(url)).to include("access_token=#{described_class::FILTERED}")
      expect(described_class.scrub_string(url)).not_to include("dmcp_secret")
    end
  end

  describe ".scrub_value" do
    it "filters sensitive hash keys" do
      input = { "access_token" => "dmcp_abc", "ok" => "hello dmcp_xyz end" }
      out = described_class.scrub_value(input)
      expect(out["access_token"]).to eq(described_class::FILTERED)
      expect(out["ok"]).to include(described_class::FILTERED)
    end
  end
end
