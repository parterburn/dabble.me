# frozen_string_literal: true

require "rails_helper"

RSpec.describe MailgunStorageClient do
  around do |example|
    original = ENV["MAILGUN_API_KEY"]
    ENV["MAILGUN_API_KEY"] = "key-secret-12345"
    example.run
  ensure
    ENV["MAILGUN_API_KEY"] = original
  end

  def ok_response(body = "bytes")
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response["content-type"] = "image/jpeg"
    allow(response).to receive(:body).and_return(body)
    response
  end

  it "downloads a storage.mailgun.net URL from api.mailgun.net with an Authorization header" do
    allow(Resolv).to receive(:getaddresses).with("api.mailgun.net").and_return(["1.1.1.1"])
    requests = []
    allow(Net::HTTP).to receive(:start).with("api.mailgun.net", 443, hash_including(ipaddr: "1.1.1.1", use_ssl: true)) do |_host, _port, **_kwargs, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |request|
        requests << request
        ok_response
      end
      block.call(http)
    end

    result = described_class.get("https://storage.mailgun.net/v3/domains/example.com/messages/abc/attachments/0")

    expect(result).to be_ok
    expect(result.body).to eq("bytes")
    expect(requests.length).to eq(1)
    request = requests.first
    expect(request.path).to eq("/v3/domains/example.com/messages/abc/attachments/0")
    expect(request.path).not_to include("key-secret-12345")
    expect(Base64.decode64(request["authorization"].sub(/\ABasic /, ""))).to eq("api:key-secret-12345")
  end

  it "does not send the API key to a host outside mailgun" do
    expect(Net::HTTP).not_to receive(:start)

    result = described_class.get("https://evil.example/v3/attachments/0")

    expect(result).not_to be_ok
    expect(result.error).not_to include("key-secret-12345")
  end

  it "does not follow a redirect off api.mailgun.net" do
    allow(Resolv).to receive(:getaddresses).with("api.mailgun.net").and_return(["1.1.1.1"])
    calls = []
    allow(Net::HTTP).to receive(:start) do |host, _port, **_kwargs, &block|
      calls << host
      http = instance_double(Net::HTTP)
      redirect = Net::HTTPFound.new("1.1", "302", "Found")
      redirect["location"] = "https://169.254.169.254/latest/meta-data"
      allow(http).to receive(:request).and_return(redirect)
      block.call(http)
    end

    result = described_class.get("https://api.mailgun.net/v3/domains/example.com/messages/abc")

    expect(result).not_to be_ok
    expect(calls).to eq(["api.mailgun.net"])
    expect(result.error).not_to include("key-secret-12345")
  end

  it "strips the API key from exception text" do
    allow(Resolv).to receive(:getaddresses).with("api.mailgun.net").and_return(["1.1.1.1"])
    allow(Net::HTTP).to receive(:start).and_raise(
      StandardError,
      "failed https://api:key-secret-12345@api.mailgun.net/v3/x key-secret-12345"
    )

    result = described_class.get("https://api.mailgun.net/v3/x")

    expect(result).not_to be_ok
    expect(result.error).not_to include("key-secret-12345")
    expect(result.error).to include("[FILTERED]")
  end
end
