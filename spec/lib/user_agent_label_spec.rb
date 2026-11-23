# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserAgentLabel do
  {
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15" => %w[Safari Mac],
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0 Mobile/15E148 Safari/604.1" => %w[Chrome iPhone],
    "Mozilla/5.0 (iPad; CPU OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1" => %w[Safari iPad],
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36 Edg/131.0" => %w[Edge Windows],
    "Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0" => %w[Firefox Linux],
    "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Mobile Safari/537.36" => %w[Chrome Android]
  }.each do |agent, (browser, os)|
    it "reads #{browser} on #{os}" do
      expect(described_class.parse(agent)).to eq(browser: browser, os: os)
    end
  end

  it "falls back to Browser with no OS" do
    expect(described_class.parse(nil)).to eq(browser: "Browser", os: nil)
  end
end
