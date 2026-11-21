# frozen_string_literal: true

module AppStore
  # Where every Apple subscription change goes through: the app's purchase or restore, an App
  # Store notification, and the nightly check. Each records what Apple says now (AppleSubscription),
  # settles which account it belongs to, records the payment, and updates the plan
  # (AppStore::Entitlement) of every account that gained or lost it.
  #
  # Which account: the one whose apple_account_token the newest transaction carries. The app
  # always sends one with a purchase, so whoever bought last owns it. A transaction without one
  # (a resubscribe from iOS Settings, an offer code) keeps the owner it had, and with no owner
  # (never claimed, or the account was deleted) the signed-in account that restores it gets it.
  # A subscription is never handed to an account other than the one the purchase names: a
  # restore from another account is refused (OtherAccount).
  module Subscriptions
    # The subscription belongs to a different Dabble Me account.
    class OtherAccount < Error
      attr_reader :owner

      def initialize(owner)
        @owner = owner
        super("This App Store subscription belongs to another Dabble Me account.")
      end
    end

    class FamilyShared < Error; end

    module_function

    # POST /api/v1/apple_subscriptions: a transaction StoreKit verified on the phone, signed by
    # Apple. Apple's API is asked for the subscription's current state; if it can't be reached,
    # the transaction itself is used (it's Apple-signed, and older state never wins over newer).
    def claim!(user:, signed_transaction:)
      snapshot = Snapshot.new(transaction: SignedData.verify!(signed_transaction)).validate!
      raise FamilyShared, "Family Sharing purchases don't include PRO." if snapshot.family_shared?

      named = snapshot.app_account_token && User.find_by(apple_account_token: snapshot.app_account_token)
      raise OtherAccount, named if named && named != user

      current = begin
        current_snapshot(snapshot.original_transaction_id, snapshot.environment)
      rescue TransientError, ApiError => e
        Sentry.capture_exception(e, level: :warning, extra: { original_transaction_id: snapshot.original_transaction_id })
        nil
      end
      record!(current || snapshot, claimant: user, payment_snapshots: [snapshot, current].compact)
    end

    # From a notification or the nightly check: asks Apple for the state now and records it.
    # If Apple's API can't answer (or has no credentials yet), `fallback`, the notification's own
    # signed state, is recorded instead; it can't overwrite anything Apple signed later. A
    # TransientError is raised after that, so the notification is retried and the API asked again.
    def refresh!(original_transaction_id:, environment:, fallback: nil, payment_snapshots: [])
      failure = nil
      current = begin
        current_snapshot(original_transaction_id, environment)
      rescue TransientError, ApiError => e
        failure = e
        nil
      end
      current ||= fallback
      subscription = current && record!(current, payment_snapshots: payment_snapshots + [current])
      raise failure if failure.is_a?(TransientError)

      Sentry.capture_exception(failure, extra: { original_transaction_id: original_transaction_id }) if failure
      subscription
    end

    def current_snapshot(original_transaction_id, environment)
      return nil unless AppStore.api_configured?

      ServerApi.subscription_status(original_transaction_id, environment: environment).validate!
    end

    # Returns the AppleSubscription. Raises OtherAccount (after saving Apple's state) when the
    # claimant isn't the account it belongs to.
    def record!(snapshot, claimant: nil, payment_snapshots: [])
      # Family Sharing doesn't include PRO, so a family member's copy isn't kept at all.
      return nil if snapshot.family_shared?

      subscription = AppleSubscription.create_or_find_by!(original_transaction_id: snapshot.original_transaction_id) do |s|
        s.environment = snapshot.environment
        s.product_id = snapshot.product_id
        s.state_signed_at = Time.at(0).utc
      end

      previous_owner = nil
      owner = nil
      AppleSubscription.transaction do
        subscription.lock!
        previous_owner = subscription.user
        subscription.apply(snapshot)

        named = subscription.app_account_token && User.find_by(apple_account_token: subscription.app_account_token)
        owner = named || previous_owner
        owner ||= claimant
        if owner != previous_owner
          subscription.update!(user: owner)
          Sentry.capture_message("Apple subscription changed accounts", level: :info, extra: {
            original_transaction_id: subscription.original_transaction_id, from: previous_owner&.id, to: owner&.id
          }) if previous_owner
        end
      end

      record_payments(owner, payment_snapshots) if owner
      Entitlement.sync!(previous_owner) if previous_owner && previous_owner != owner
      Entitlement.sync!(owner) if owner
      raise OtherAccount, owner if claimant && owner && owner != claimant

      subscription
    end

    # A Payment per Apple transaction, once. Production only (sandbox purchases are free), and
    # an amount only in US dollars, which is what the revenue numbers add up; other currencies
    # are noted in the comment with an amount of 0.
    def record_payments(user, snapshots)
      snapshots.uniq(&:transaction_id).each do |snapshot|
        next if snapshot.environment != PRODUCTION || snapshot.price.nil? || snapshot.revoked_at || snapshot.transaction_id.blank?

        usd = snapshot.currency == "USD"
        payment = Payment.create_or_find_by!(apple_transaction_id: snapshot.transaction_id) do |p|
          p.user = user
          p.amount = usd ? snapshot.price : 0
          p.date = snapshot.purchased_at || Time.current
          p.comments = "Apple #{snapshot.yearly? ? 'Yearly' : 'Monthly'}" +
                       (usd ? "" : " (#{snapshot.currency} #{format('%.2f', snapshot.price)})")
        end
        # Charged by Apple while PRO through the web too: each such charge is a double payment.
        if payment.previously_new_record? && user.reload.is_pro? && !Entitlement.apple_plan?(user)
          UserMailer.apple_double_billing(user, snapshot.transaction_id).deliver_later
        end
      end
    end
  end
end
