# frozen_string_literal: true

# A stand-in for Apple's signing chain (root → WWDR intermediate → App Store leaf, with Apple's
# marker extensions) so specs sign transactions, renewal info, notifications and API answers
# the way Apple does, and AppStore::SignedData verifies them for real against this root.
module AppStoreHelpers
  class FakeApplePki
    attr_reader :root, :intermediate, :leaf, :leaf_key

    def initialize(leaf_oid: AppStore::SignedData::LEAF_OID, intermediate_oid: AppStore::SignedData::INTERMEDIATE_OID,
                   leaf_not_after: 1.year.from_now)
      root_key = OpenSSL::PKey::EC.generate("prime256v1")
      @root = cert("Fake Apple Root CA - G3", root_key, root_key, nil, ca: true)
      intermediate_key = OpenSSL::PKey::EC.generate("prime256v1")
      @intermediate = cert("Fake Apple WWDR", intermediate_key, root_key, @root, ca: true, oid: intermediate_oid)
      @leaf_key = OpenSSL::PKey::EC.generate("prime256v1")
      @leaf = cert("Fake Prod ECC Mac App Store", @leaf_key, intermediate_key, @intermediate, oid: leaf_oid, not_after: leaf_not_after)
    end

    def sign(payload, key: leaf_key, chain: [leaf, intermediate, root])
      JWT.encode(payload, key, "ES256", { x5c: chain.map { |c| Base64.strict_encode64(c.to_der) } })
    end

    private

    def cert(name, key, issuer_key, issuer, ca: false, oid: nil, not_after: 5.years.from_now)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = SecureRandom.random_number(2**64)
      cert.subject = OpenSSL::X509::Name.parse("/CN=#{name}/O=Apple Inc./C=US")
      cert.issuer = issuer ? issuer.subject : cert.subject
      cert.public_key = key
      cert.not_before = 1.day.ago
      cert.not_after = not_after
      factory = OpenSSL::X509::ExtensionFactory.new
      factory.subject_certificate = cert
      factory.issuer_certificate = issuer || cert
      cert.add_extension(factory.create_extension("basicConstraints", ca ? "CA:TRUE" : "CA:FALSE", true))
      cert.add_extension(factory.create_extension("keyUsage", ca ? "keyCertSign,cRLSign" : "digitalSignature", true))
      cert.add_extension(OpenSSL::X509::Extension.new(oid, OpenSSL::ASN1::Null.new(nil).to_der)) if oid
      cert.sign(issuer_key, OpenSSL::Digest.new("SHA256"))
      cert
    end
  end

  def apple_pki
    @apple_pki ||= FakeApplePki.new
  end

  def ms(time) = (time.to_f * 1000).to_i

  def apple_transaction(user: nil, **overrides)
    now = Time.current
    {
      "transactionId" => "2000000#{SecureRandom.random_number(10**8)}",
      "originalTransactionId" => "1000000001",
      "webOrderLineItemId" => "3000000001",
      "bundleId" => AppStore::BUNDLE_ID,
      "productId" => AppStore::MONTHLY_PRODUCT_ID,
      "subscriptionGroupIdentifier" => "21000001",
      "purchaseDate" => ms(now - 1.minute),
      "originalPurchaseDate" => ms(now - 1.minute),
      "expiresDate" => ms(now + 1.month),
      "quantity" => 1,
      "type" => "Auto-Renewable Subscription",
      "appAccountToken" => user&.apple_account_token!,
      "inAppOwnershipType" => "PURCHASED",
      "signedDate" => ms(now),
      "environment" => "Sandbox",
      "transactionReason" => "PURCHASE",
      "storefront" => "USA",
      "price" => 3990,
      "currency" => "USD"
    }.merge(overrides.transform_keys(&:to_s)).compact
  end

  def apple_renewal(transaction, **overrides)
    {
      "originalTransactionId" => transaction["originalTransactionId"],
      "autoRenewProductId" => transaction["productId"],
      "productId" => transaction["productId"],
      "autoRenewStatus" => 1,
      "signedDate" => transaction["signedDate"],
      "environment" => transaction["environment"],
      "renewalDate" => transaction["expiresDate"]
    }.merge(overrides.transform_keys(&:to_s)).compact
  end

  def apple_notification(type, transaction, subtype: nil, renewal: nil, status: nil, uuid: SecureRandom.uuid, signed_at: Time.current, **data)
    {
      "notificationType" => type,
      "subtype" => subtype,
      "notificationUUID" => uuid,
      "version" => "2.0",
      "signedDate" => ms(signed_at),
      "data" => {
        "appAppleId" => 1_234_567_890,
        "bundleId" => AppStore::BUNDLE_ID,
        "bundleVersion" => "110",
        "environment" => transaction["environment"],
        "signedTransactionInfo" => apple_pki.sign(transaction),
        "signedRenewalInfo" => renewal && apple_pki.sign(renewal),
        "status" => status
      }.merge(data.transform_keys { |k| k.to_s.camelize(:lower) }).compact
    }.compact
  end

  # Apple's Get All Subscription Statuses answer for one subscription.
  def stub_apple_status(transaction, status: 1, renewal: apple_renewal(transaction), environment: transaction["environment"])
    host = AppStore::ServerApi::HOSTS.fetch(environment)
    stub_request(:get, "https://#{host}/inApps/v1/subscriptions/#{transaction['originalTransactionId']}").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        environment: environment,
        bundleId: AppStore::BUNDLE_ID,
        appAppleId: 1_234_567_890,
        data: [{
          subscriptionGroupIdentifier: "21000001",
          lastTransactions: [{
            originalTransactionId: transaction["originalTransactionId"],
            status: status,
            signedTransactionInfo: apple_pki.sign(transaction),
            signedRenewalInfo: renewal && apple_pki.sign(renewal)
          }]
        }]
      }.to_json
    )
  end

  # (with_env is EncryptionHelpers'.)
  def with_app_store_api(&)
    with_env(
      "APP_STORE_CONNECT_ISSUER_ID" => "57246542-96fe-1a63-e053-0824d011072a",
      "APP_STORE_CONNECT_KEY_ID" => "2X9R4HXF34",
      "APP_STORE_CONNECT_PRIVATE_KEY" => OpenSSL::PKey::EC.generate("prime256v1").to_pem,
      &
    )
  end
end

RSpec.configure do |config|
  config.include AppStoreHelpers

  config.before(:each) do
    AppStore::SignedData.root_certificates = [apple_pki.root]
  end

  config.after(:each) do
    AppStore::SignedData.root_certificates = nil
  end
end
