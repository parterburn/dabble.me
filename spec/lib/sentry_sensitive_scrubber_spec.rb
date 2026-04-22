require "rails_helper"
require Rails.root.join("lib/sentry_sensitive_scrubber")

RSpec.describe SentrySensitiveScrubber do
  describe ".scrub_string" do
    it "redacts Bearer header values" do
      expect(described_class.scrub_string("Authorization: Bearer oauth_secret_123")).to include(described_class::FILTERED)
      expect(described_class.scrub_string("Authorization: Bearer oauth_secret_123")).not_to include("oauth_secret")
    end

    it "redacts access_token query segments" do
      url = "https://example.com/mcp?access_token=at_secret&foo=1"
      expect(described_class.scrub_string(url)).to include("access_token=#{described_class::FILTERED}")
      expect(described_class.scrub_string(url)).not_to include("at_secret")
    end
  end

  describe ".scrub_value" do
    it "filters sensitive hash keys" do
      input = { "access_token" => "secret123", "ok" => "plain" }
      out = described_class.scrub_value(input)
      expect(out["access_token"]).to eq(described_class::FILTERED)
      expect(out["ok"]).to eq("plain")
    end
  end
end
