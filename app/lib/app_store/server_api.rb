# frozen_string_literal: true

require "net/http"

module AppStore
  # App Store Server API: Get All Subscription Statuses, the one call this needs.
  # https://developer.apple.com/documentation/appstoreserverapi/get_all_subscription_statuses
  #
  # Authenticated with a short-lived ES256 token signed by the In-App Purchase key
  # (APP_STORE_CONNECT_* variables, see AppStore).
  module ServerApi
    HOSTS = {
      PRODUCTION => "api.storekit.itunes.apple.com",
      SANDBOX => "api.storekit-sandbox.itunes.apple.com"
    }.freeze
    TOKEN_LIFETIME = 5.minutes
    HTTP_TIMEOUT = 10

    module_function

    def configured?
      issuer_id.present? && key_id.present? && private_key_pem.present?
    end

    # The subscription's current state, as Snapshot, verified like everything else Apple signs.
    # Raises TransientError when Apple can't answer now and ApiError when it refuses.
    def subscription_status(original_transaction_id, environment:)
      raise ApiError, "App Store Server API is not configured" unless configured?

      host = HOSTS.fetch(environment) { raise ApiError, "unknown environment #{environment}" }
      body = get(host, "/inApps/v1/subscriptions/#{ERB::Util.url_encode(original_transaction_id)}")
      raise VerificationError, "status is for another app" unless body["bundleId"] == BUNDLE_ID
      raise VerificationError, "status is from another environment" unless body["environment"] == environment

      entry = Array(body["data"]).flat_map { |group| Array(group["lastTransactions"]) }
                                 .find { |last| last["originalTransactionId"].to_s == original_transaction_id.to_s }
      raise ApiError.new("no status for #{original_transaction_id}", status: 404) unless entry

      Snapshot.new(
        transaction: SignedData.verify!(entry["signedTransactionInfo"]),
        renewal: entry["signedRenewalInfo"].present? ? SignedData.verify!(entry["signedRenewalInfo"]) : nil,
        status: entry["status"]
      )
    end

    def get(host, path)
      uri = URI::HTTPS.build(host: host, path: path)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Accept"] = "application/json"
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) { |http| http.request(request) }

      case response.code.to_i
      when 200 then JSON.parse(response.body)
      when 429, 500..599 then raise TransientError, "App Store Server API answered #{response.code}"
      else raise ApiError.new("App Store Server API answered #{response.code}: #{response.body.to_s.first(300)}", status: response.code.to_i)
      end
    rescue SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError, IOError, EOFError, Net::HTTPBadResponse => e
      raise TransientError, "App Store Server API unreachable (#{e.class})"
    rescue JSON::ParserError
      raise TransientError, "App Store Server API sent something that isn't JSON"
    end

    def token
      now = Time.current.to_i
      JWT.encode(
        { iss: issuer_id, iat: now, exp: now + TOKEN_LIFETIME.to_i, aud: "appstoreconnect-v1", bid: BUNDLE_ID },
        OpenSSL::PKey::EC.new(private_key_pem),
        "ES256",
        { kid: key_id, typ: "JWT" }
      )
    end

    def issuer_id = ENV["APP_STORE_CONNECT_ISSUER_ID"].to_s.strip.presence
    def key_id = ENV["APP_STORE_CONNECT_KEY_ID"].to_s.strip.presence

    # Railway keeps the .p8's newlines; a value pasted with literal "\n"s works too.
    def private_key_pem
      ENV["APP_STORE_CONNECT_PRIVATE_KEY"].to_s.strip.gsub("\\n", "\n").presence
    end
  end
end
