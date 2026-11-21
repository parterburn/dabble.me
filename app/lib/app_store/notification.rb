# frozen_string_literal: true

module AppStore
  # One App Store Server Notification V2 (POST /app_store/notifications, {"signedPayload": JWS}).
  #
  # Verified, checked to be for this app and an environment this server takes, recorded once by
  # its notificationUUID, and then used only as a prompt: the subscription it names is refreshed
  # from Apple's API (AppStore::Subscriptions.refresh!), whatever the notification's type. So it
  # doesn't matter if notifications arrive twice or out of order, and no notification type needs
  # its own handling to be right (SUBSCRIBED, DID_RENEW, DID_FAIL_TO_RENEW with or without
  # GRACE_PERIOD, GRACE_PERIOD_EXPIRED, EXPIRED, REFUND, REFUND_REVERSED, REVOKE,
  # DID_CHANGE_RENEWAL_PREF/STATUS, OFFER_REDEEMED, RENEWAL_EXTENDED, ...).
  module Notification
    # Types that carry no subscription to refresh.
    IGNORED_TYPES = %w[TEST CONSUMPTION_REQUEST RENEWAL_EXTENSION EXTERNAL_PURCHASE_TOKEN].freeze

    module_function

    # Returns the AppStoreNotification. Raises VerificationError for anything not Apple's or
    # not for this app, and TransientError when it should be redelivered.
    def process!(signed_payload)
      payload = SignedData.verify!(signed_payload)
      data = payload["data"].is_a?(Hash) ? payload["data"] : {}
      environment = data["environment"]
      uuid = payload["notificationUUID"].to_s
      raise VerificationError, "notification has no UUID" if uuid.blank?
      raise VerificationError, "notification is for another app" unless data["bundleId"] == BUNDLE_ID
      raise VerificationError, "#{environment.inspect} notifications are not accepted here" unless AppStore.allowed_environments.include?(environment)
      if environment == PRODUCTION && AppStore.app_apple_id && data["appAppleId"].to_i != AppStore.app_apple_id
        raise VerificationError, "notification is for another app ID"
      end

      record = AppStoreNotification.create_or_find_by!(notification_uuid: uuid) do |n|
        n.notification_type = payload["notificationType"].to_s.presence || "UNKNOWN"
        n.subtype = payload["subtype"]
        n.environment = environment
        n.signed_at = SignedData.time(payload["signedDate"])
      end
      return record if record.processed_at

      handle(record, data)
      record.update!(processed_at: Time.current)
      record
    end

    def handle(record, data)
      return if IGNORED_TYPES.include?(record.notification_type)
      return if data["signedTransactionInfo"].blank?

      snapshot = Snapshot.new(
        transaction: SignedData.verify!(data["signedTransactionInfo"]),
        renewal: data["signedRenewalInfo"].present? ? SignedData.verify!(data["signedRenewalInfo"]) : nil,
        status: data["status"]
      ).validate!
      raise VerificationError, "transaction is from another environment" unless snapshot.environment == data["environment"]

      record.update!(original_transaction_id: snapshot.original_transaction_id)
      Subscriptions.refresh!(
        original_transaction_id: snapshot.original_transaction_id,
        environment: snapshot.environment,
        fallback: snapshot,
        payment_snapshots: [snapshot]
      )
    end
  end
end
