# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::OauthRules do
  describe ".allowed_resource?" do
    let(:base) { "https://dabble.me" }

    it "accepts no resource, the MCP endpoint and the bare origin" do
      expect(described_class.allowed_resource?(nil, base)).to be(true)
      expect(described_class.allowed_resource?("", base)).to be(true)
      expect(described_class.allowed_resource?("https://dabble.me/mcp", base)).to be(true)
      expect(described_class.allowed_resource?("https://dabble.me/mcp/", base)).to be(true)
      expect(described_class.allowed_resource?("https://DABBLE.me:443/mcp", base)).to be(true)
      expect(described_class.allowed_resource?("https://dabble.me", base)).to be(true)
    end

    it "refuses any other server, path, scheme or a resource with a fragment or query" do
      [
        "https://evil.example/mcp",
        "https://dabble.me.evil.example/mcp",
        "https://dabble.me/api/v1",
        "http://dabble.me/mcp",
        "https://dabble.me:8443/mcp",
        "https://dabble.me/mcp#x",
        "https://dabble.me/mcp?x=1",
        "not a uri",
        "/mcp"
      ].each do |resource|
        expect(described_class.allowed_resource?(resource, base)).to be(false), resource
      end
    end

    it "refuses a list when any entry is foreign" do
      expect(described_class.allowed_resource?(["https://dabble.me/mcp", "https://evil.example"], base)).to be(false)
    end
  end

  describe ".exact_redirect_uri?" do
    it "matches a registered URI exactly, one of several" do
      expect(described_class.exact_redirect_uri?("https://a.example/cb", "https://b.example/cb\nhttps://a.example/cb")).to be(true)
    end

    it "refuses extra query, a different path or case" do
      expect(described_class.exact_redirect_uri?("https://a.example/cb?next=x", "https://a.example/cb")).to be(false)
      expect(described_class.exact_redirect_uri?("https://a.example/cb/", "https://a.example/cb")).to be(false)
      expect(described_class.exact_redirect_uri?("https://a.example/CB", "https://a.example/cb")).to be(false)
    end

    it "lets only a loopback redirect change port" do
      expect(described_class.exact_redirect_uri?("http://127.0.0.1:53111/cb", "http://127.0.0.1/cb")).to be(true)
      expect(described_class.exact_redirect_uri?("http://localhost:6274/cb", "http://localhost:3000/cb")).to be(true)
      expect(described_class.exact_redirect_uri?("http://127.0.0.1:53111/other", "http://127.0.0.1/cb")).to be(false)
      expect(described_class.exact_redirect_uri?("https://a.example:8443/cb", "https://a.example/cb")).to be(false)
    end

    it "matches the iOS app's private-use scheme" do
      expect(described_class.exact_redirect_uri?(MobileApp::REDIRECT_URI, MobileApp::REDIRECT_URI)).to be(true)
    end
  end
end
