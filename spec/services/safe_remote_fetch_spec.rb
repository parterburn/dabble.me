# frozen_string_literal: true

require "rails_helper"

RSpec.describe SafeRemoteFetch do
  def http_response(klass, code, headers = {}, body = "")
    response = klass.new("1.1", code, "OK")
    headers.each { |key, value| response[key] = value }
    allow(response).to receive(:body).and_return(body)
    allow(response).to receive(:read_body) do |&blk|
      blk&.call(body.to_s)
      body
    end
    response
  end

  def stub_start
    calls = []
    allow(Net::HTTP).to receive(:start) do |host, port, **kwargs, &block|
      calls << { host: host, port: port, ipaddr: kwargs[:ipaddr], use_ssl: kwargs[:use_ssl] }
      http = instance_double(Net::HTTP)
      response = yield(host)
      allow(http).to receive(:request) do |_request, &request_block|
        request_block&.call(response)
        response
      end
      block.call(http)
    end
    calls
  end

  it "pins the connection to the resolved public address" do
    allow(Resolv).to receive(:getaddresses).with("images.example.com").and_return(["93.184.216.34"])
    calls = stub_start { http_response(Net::HTTPOK, "200", { "content-type" => "image/jpeg" }, "jpeg") }

    result = described_class.fetch("https://images.example.com/photo.jpg")

    expect(result).to be_ok
    expect(result.body).to eq("jpeg")
    expect(calls).to eq([{ host: "images.example.com", port: 443, ipaddr: "93.184.216.34", use_ssl: true }])
  end

  it "rejects a redirect onto a private or link-local address without connecting to it" do
    allow(Resolv).to receive(:getaddresses).with("images.example.com").and_return(["93.184.216.34"])
    calls = stub_start do
      http_response(Net::HTTPFound, "302", { "location" => "http://169.254.169.254/latest/meta-data" })
    end

    result = described_class.fetch("https://images.example.com/photo.jpg")

    expect(result).not_to be_ok
    expect(result.error).to eq(:private_host)
    expect(calls.map { |call| call[:host] }).to eq(["images.example.com"])
  end

  it "rejects loopback, private, link-local, and credential URLs before connecting" do
    expect(Net::HTTP).not_to receive(:start)

    expect(described_class.fetch("http://127.0.0.1/secret").error).to eq(:private_host)
    expect(described_class.fetch("http://10.0.0.8/secret").error).to eq(:private_host)
    expect(described_class.fetch("http://169.254.169.254/latest/meta-data").error).to eq(:private_host)
    expect(described_class.fetch("http://100.64.0.1/secret").error).to eq(:private_host)
    expect(described_class.fetch("https://user:pass@images.example.com/a.jpg").error).to eq(:credentials)
  end

  it "rejects a host when any resolved address is private" do
    allow(Resolv).to receive(:getaddresses).with("mixed.example.com").and_return(["93.184.216.34", "10.1.1.1"])
    expect(Net::HTTP).not_to receive(:start)

    expect(described_class.fetch("https://mixed.example.com/a.jpg").error).to eq(:private_host)
  end

  it "requires https for every hop when asked" do
    allow(Resolv).to receive(:getaddresses).with("images.example.com").and_return(["93.184.216.34"])
    stub_start { http_response(Net::HTTPFound, "302", { "location" => "http://images.example.com/plain.jpg" }) }

    result = described_class.fetch("https://images.example.com/photo.jpg", https_only: true)

    expect(result.error).to eq(:https_required)
  end

  it "rejects an oversized Content-Length before reading the body" do
    allow(Resolv).to receive(:getaddresses).with("images.example.com").and_return(["93.184.216.34"])
    response = http_response(Net::HTTPOK, "200", { "content-length" => 21.megabytes.to_s }, "")
    expect(response).not_to receive(:read_body)
    stub_start { response }

    result = described_class.fetch("https://images.example.com/photo.jpg")

    expect(result.error).to eq(:too_large)
  end

  it "stops streaming a success body once the cap is passed" do
    allow(Resolv).to receive(:getaddresses).with("images.example.com").and_return(["93.184.216.34"])
    response = Net::HTTPOK.new("1.1", "200", "OK")
    reads = 0
    allow(response).to receive(:read_body) do |&blk|
      4.times do
        reads += 1
        blk.call("123456")
      end
    end
    stub_start { response }

    result = described_class.fetch("https://images.example.com/photo.jpg", max_bytes: 10)

    expect(result.error).to eq(:too_large)
    expect(reads).to eq(2)
  end

  it "does not follow a redirect whose body exceeds the cap" do
    allow(Resolv).to receive(:getaddresses).with("images.example.com").and_return(["93.184.216.34"])
    response = http_response(
      Net::HTTPFound,
      "302",
      { "location" => "https://images.example.com/next.jpg", "content-length" => 21.megabytes.to_s },
      ""
    )
    expect(response).not_to receive(:read_body)
    calls = stub_start { response }

    result = described_class.fetch("https://images.example.com/photo.jpg")

    expect(result.error).to eq(:too_large)
    expect(calls.size).to eq(1)
  end

  it "stops streaming a redirect body once the cap is passed and does not follow it" do
    allow(Resolv).to receive(:getaddresses).with("images.example.com").and_return(["93.184.216.34"])
    response = Net::HTTPFound.new("1.1", "302", "Found")
    response["location"] = "https://images.example.com/next.jpg"
    reads = 0
    allow(response).to receive(:read_body) do |&blk|
      4.times do
        reads += 1
        blk.call("123456")
      end
    end
    calls = stub_start { response }

    result = described_class.fetch("https://images.example.com/photo.jpg", max_bytes: 10)

    expect(result.error).to eq(:too_large)
    expect(reads).to eq(2)
    expect(calls.size).to eq(1)
  end
end
