# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppStore::SignedData do
  let(:payload) { { "transactionId" => "1", "signedDate" => ms(Time.current) } }

  it "returns the payload of a JWS signed by an App Store leaf under the trusted root" do
    expect(described_class.verify!(apple_pki.sign(payload))).to eq(payload)
  end

  it "trusts only the root kept in config/certs by default, which is Apple Root CA - G3" do
    described_class.root_certificates = nil
    root = described_class.root_certificates.first
    expect(root.subject.to_s).to include("Apple Root CA - G3")
    expect(OpenSSL::Digest::SHA256.hexdigest(root.to_der).upcase)
      .to eq("63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179")
    expect { described_class.verify!(apple_pki.sign(payload)) }.to raise_error(AppStore::VerificationError, /root/)
  end

  it "refuses a chain under any other root, even one shaped exactly like Apple's" do
    other = AppStoreHelpers::FakeApplePki.new
    expect { described_class.verify!(other.sign(payload)) }.to raise_error(AppStore::VerificationError, /root/)
  end

  it "refuses a chain whose root is Apple's but whose intermediate isn't signed by it" do
    other = AppStoreHelpers::FakeApplePki.new
    jws = other.sign(payload, chain: [other.leaf, other.intermediate, apple_pki.root])
    expect { described_class.verify!(jws) }.to raise_error(AppStore::VerificationError, /did not verify/)
  end

  it "refuses a leaf without the App Store signing marker" do
    pki = AppStoreHelpers::FakeApplePki.new(leaf_oid: nil)
    described_class.root_certificates = [pki.root]
    expect { described_class.verify!(pki.sign(payload)) }.to raise_error(AppStore::VerificationError, /leaf/)
  end

  it "refuses an intermediate without the WWDR marker" do
    pki = AppStoreHelpers::FakeApplePki.new(intermediate_oid: nil)
    described_class.root_certificates = [pki.root]
    expect { described_class.verify!(pki.sign(payload)) }.to raise_error(AppStore::VerificationError, /intermediate/)
  end

  it "refuses an expired leaf" do
    pki = AppStoreHelpers::FakeApplePki.new(leaf_not_after: 1.hour.ago)
    described_class.root_certificates = [pki.root]
    expect { described_class.verify!(pki.sign(payload)) }.to raise_error(AppStore::VerificationError, /did not verify/)
  end

  it "refuses a JWS signed by a key other than the leaf's" do
    jws = apple_pki.sign(payload, key: OpenSSL::PKey::EC.generate("prime256v1"))
    expect { described_class.verify!(jws) }.to raise_error(AppStore::VerificationError, /signature/)
  end

  it "refuses a payload changed after signing" do
    header, _, signature = apple_pki.sign(payload).split(".")
    forged = Base64.urlsafe_encode64(payload.merge("expiresDate" => ms(10.years.from_now)).to_json, padding: false)
    expect { described_class.verify!([header, forged, signature].join(".")) }.to raise_error(AppStore::VerificationError)
  end

  it "refuses other algorithms, including none and HMAC" do
    x5c = [apple_pki.leaf, apple_pki.intermediate, apple_pki.root].map { |c| Base64.strict_encode64(c.to_der) }
    hmac = JWT.encode(payload, apple_pki.leaf.public_key.to_der, "HS256", { x5c: x5c })
    none = JWT.encode(payload, nil, "none", { x5c: x5c })
    expect { described_class.verify!(hmac) }.to raise_error(AppStore::VerificationError, /algorithm/)
    expect { described_class.verify!(none) }.to raise_error(AppStore::VerificationError)
  end

  it "refuses a chain that isn't exactly leaf, intermediate and root" do
    jws = apple_pki.sign(payload, chain: [apple_pki.leaf, apple_pki.root])
    expect { described_class.verify!(jws) }.to raise_error(AppStore::VerificationError, /chain/)
  end

  it "refuses things that aren't a JWS" do
    [nil, "", "abc", "a.b", "a.b.c", 123].each do |junk|
      expect { described_class.verify!(junk) }.to raise_error(AppStore::VerificationError)
    end
  end
end
