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

    it "redacts URL userinfo credentials such as api:MAILGUN_API_KEY@" do
      url = "https://api:key-secret-12345@api.mailgun.net/v3/domains/messages/1/attachments/0?photo.jpg"
      scrubbed = described_class.scrub_string(url)
      expect(scrubbed).to eq("https://#{described_class::FILTERED}@api.mailgun.net/v3/domains/messages/1/attachments/0?photo.jpg")
      expect(scrubbed).not_to include("key-secret-12345")
    end
  end

  describe ".scrub_value" do
    it "filters sensitive hash keys" do
      input = { "access_token" => "secret123", "ok" => "plain" }
      out = described_class.scrub_value(input)
      expect(out["access_token"]).to eq(described_class::FILTERED)
      expect(out["ok"]).to eq("plain")
    end

    it "filters private journal content keys including entry[entry] and entry[ai_response]" do
      input = {
        "body" => "private journal text",
        "raw_body" => "full email body",
        "html" => "<p>private</p>",
        "stripped_html" => "<p>stripped</p>",
        "original_email_body" => "original",
        "original_email" => { "body-plain" => "plain" },
        "text_body" => "mcp text",
        "ai_response" => "top-level ai reply",
        "subject" => "Sunday journal",
        "params" => {
          "entry" => {
            "body" => "nested private",
            "entry" => "web form journal body",
            "ai_response" => "nested ai reply",
            "date" => "2026-07-15"
          }
        }
      }
      out = described_class.scrub_value(input)
      expect(out["body"]).to eq(described_class::FILTERED)
      expect(out["raw_body"]).to eq(described_class::FILTERED)
      expect(out["html"]).to eq(described_class::FILTERED)
      expect(out["stripped_html"]).to eq(described_class::FILTERED)
      expect(out["original_email_body"]).to eq(described_class::FILTERED)
      expect(out["original_email"]).to eq(described_class::FILTERED)
      expect(out["text_body"]).to eq(described_class::FILTERED)
      expect(out["ai_response"]).to eq(described_class::FILTERED)
      expect(out["subject"]).to eq("Sunday journal")
      expect(out["params"]["entry"]["body"]).to eq(described_class::FILTERED)
      expect(out["params"]["entry"]["entry"]).to eq(described_class::FILTERED)
      expect(out["params"]["entry"]["ai_response"]).to eq(described_class::FILTERED)
      expect(out["params"]["entry"]["date"]).to eq("2026-07-15")
    end
  end
end
