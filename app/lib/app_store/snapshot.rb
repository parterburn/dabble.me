# frozen_string_literal: true

module AppStore
  # One verified look at a subscription: its latest transaction, its renewal info when Apple
  # sent it, and Apple's status number when known (from the Server API or a notification).
  class Snapshot
    STATUS_ACTIVE = 1
    STATUS_EXPIRED = 2
    STATUS_BILLING_RETRY = 3
    STATUS_GRACE_PERIOD = 4
    STATUS_REVOKED = 5
    STATUSES = [STATUS_ACTIVE, STATUS_EXPIRED, STATUS_BILLING_RETRY, STATUS_GRACE_PERIOD, STATUS_REVOKED].freeze
    AUTO_RENEWABLE = "Auto-Renewable Subscription"
    FAMILY_SHARED = "FAMILY_SHARED"

    attr_reader :transaction, :renewal

    def initialize(transaction:, renewal: nil, status: nil)
      @transaction = transaction
      @renewal = renewal
      @status = status.presence&.to_i
    end

    # Refuses anything that isn't one of this app's PRO subscriptions in an environment this
    # server takes, and renewal info that belongs to another subscription.
    def validate!
      raise VerificationError, "transaction is for another app" unless transaction["bundleId"] == BUNDLE_ID
      raise VerificationError, "#{environment.inspect} purchases are not accepted here" unless AppStore.allowed_environments.include?(environment)
      raise VerificationError, "not an auto-renewable subscription" unless transaction["type"] == AUTO_RENEWABLE
      raise VerificationError, "unknown product #{product_id.inspect}" unless PRODUCT_IDS.include?(product_id)
      raise VerificationError, "transaction has no original transaction ID" if original_transaction_id.blank?
      raise VerificationError, "unknown status #{@status}" if @status && !STATUSES.include?(@status)

      if renewal
        raise VerificationError, "renewal info is for another subscription" unless renewal["originalTransactionId"].to_s == original_transaction_id
        raise VerificationError, "renewal info is from another environment" unless renewal["environment"] == environment
      end
      self
    end

    def original_transaction_id = transaction["originalTransactionId"].to_s
    def transaction_id = transaction["transactionId"].to_s
    def environment = transaction["environment"]
    def product_id = transaction["productId"]
    def ownership_type = transaction["inAppOwnershipType"]
    def family_shared? = ownership_type == FAMILY_SHARED
    # An upgrade's old transaction: the new one has the subscription's state, not this.
    def upgraded? = transaction["isUpgraded"] == true

    def app_account_token
      token = transaction["appAccountToken"].to_s.strip.downcase
      token.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) ? token : nil
    end

    def expires_at = SignedData.time(transaction["expiresDate"])
    def revoked_at = SignedData.time(transaction["revocationDate"])
    def purchased_at = SignedData.time(transaction["purchaseDate"])
    def grace_period_expires_at = SignedData.time(renewal&.dig("gracePeriodExpiresDate"))
    def auto_renew = renewal ? renewal["autoRenewStatus"].to_i == 1 : nil
    def auto_renew_product_id = renewal&.dig("autoRenewProductId")

    # When Apple signed the newest part of it: stored state signed later wins over this.
    def signed_at
      [transaction["signedDate"], renewal&.dig("signedDate")].compact.map { |ms| SignedData.time(ms) }.max
    end

    # Apple's number, or, with only a transaction to go on, what its dates say.
    def status(now: Time.current)
      return @status if @status
      return STATUS_REVOKED if revoked_at
      return STATUS_GRACE_PERIOD if grace_period_expires_at&.future? && renewal&.dig("isInBillingRetryPeriod")
      return STATUS_BILLING_RETRY if renewal&.dig("isInBillingRetryPeriod")

      expires_at && expires_at > now ? STATUS_ACTIVE : STATUS_EXPIRED
    end

    def yearly? = product_id == YEARLY_PRODUCT_ID

    # The customer's price, in the storefront's currency (Apple sends milliunits).
    def price
      transaction["price"].present? ? (transaction["price"].to_i / 1000.0) : nil
    end

    def currency = transaction["currency"]
  end
end
