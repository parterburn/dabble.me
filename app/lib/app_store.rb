# frozen_string_literal: true

# Dabble Me PRO bought in the iOS app with StoreKit 2.
#
# The app buys with appAccountToken set to the account's `apple_account_token`, then posts the
# signed transaction to /api/v1/apple_subscriptions. App Store Server Notifications V2 arrive at
# /app_store/notifications. Neither is trusted for what it says about the present: each is
# verified (AppStore::SignedData), then Apple's App Store Server API is asked for the
# subscription's current status (AppStore::ServerApi), and that is what's stored
# (AppleSubscription) and turned into the account's plan (AppStore::Entitlement). That makes
# redelivered and out-of-order notifications harmless.
#
# | Variable | Purpose |
# |----------|---------|
# | APP_STORE_CONNECT_ISSUER_ID | In-App Purchase key's issuer (App Store Connect → Users and Access → Integrations) |
# | APP_STORE_CONNECT_KEY_ID | That key's ID |
# | APP_STORE_CONNECT_PRIVATE_KEY | The .p8 file's contents (PEM) |
# | APP_STORE_APP_APPLE_ID | The app's numeric Apple ID; production notifications must name it |
# | APP_STORE_ALLOW_SANDBOX | "false" refuses sandbox purchases. Leave it on: App Review and TestFlight buy in sandbox against production. |
module AppStore
  BUNDLE_ID = MobileApp::APP_ID.split(".", 2).last # me.dabble.ios
  MONTHLY_PRODUCT_ID = "#{BUNDLE_ID}.pro.monthly"
  YEARLY_PRODUCT_ID = "#{BUNDLE_ID}.pro.yearly"
  PRODUCT_IDS = [MONTHLY_PRODUCT_ID, YEARLY_PRODUCT_ID].freeze

  PRODUCTION = "Production"
  SANDBOX = "Sandbox"

  class Error < StandardError; end
  # The signed data isn't Apple's, or isn't for this app.
  class VerificationError < Error; end
  # Genuinely Apple's, but not something this server takes (another app, an environment that's
  # switched off, a product it doesn't sell). Answered 200 so Apple stops redelivering it.
  class Ignored < Error; end
  # Apple's API couldn't answer now; worth trying again later.
  class TransientError < Error; end
  # Apple's API refused the request (bad credentials, unknown transaction).
  class ApiError < Error
    attr_reader :status

    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  module_function

  def allowed_environments
    envs = [PRODUCTION]
    envs << SANDBOX unless ENV["APP_STORE_ALLOW_SANDBOX"].to_s.strip.casecmp?("false")
    # Development and test never take real money.
    envs.delete(PRODUCTION) unless Rails.env.production?
    envs
  end

  def app_apple_id
    ENV["APP_STORE_APP_APPLE_ID"].to_s.strip.presence&.to_i
  end

  def api_configured?
    ServerApi.configured?
  end

  # "p***@gmail.com": enough for someone to recognize their own other account.
  def mask_email(email)
    local, domain = email.to_s.split("@", 2)
    return "another account" if local.blank? || domain.blank?

    "#{local[0]}***@#{domain}"
  end
end
