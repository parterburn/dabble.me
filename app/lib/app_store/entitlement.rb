# frozen_string_literal: true

module AppStore
  # Turns an account's Apple subscriptions into its plan ("PRO Monthly Apple" / "PRO Yearly
  # Apple"). It only ever takes away PRO that Apple gave: an account that's PRO through Stripe,
  # Gumroad, PayPal or Forever keeps its plan whatever Apple says, and a Free account whose
  # Apple subscription is active becomes PRO. So does a Stripe plan whose Stripe subscription
  # has already ended but that the expiry check (UserDowngradeExpiredWorker) hasn't caught up
  # with yet: Stripe is asked. Gumroad and PayPal can't be, so those wait for the expiry check.
  module Entitlement
    APPLE_PLAN = /apple/i

    module_function

    def apple_plan?(user)
      user.plan.to_s.match?(APPLE_PLAN)
    end

    # The subscription that gives PRO now (yearly over monthly if, oddly, there are two).
    def active_subscription(user)
      user.apple_subscriptions.select(&:entitles_pro?).max_by { |s| [s.yearly? ? 1 : 0, s.expires_at || Time.at(0)] }
    end

    def sync!(user)
      return unless user

      upgraded = false
      downgraded = false
      # Asked before the lock: Stripe is a network call.
      lapsed = !apple_plan?(user) && user.is_pro? && active_subscription(user) && lapsed_stripe_plan?(user)
      user.with_lock do
        active = active_subscription(user)
        if active && (apple_plan?(user) || user.is_free? || (lapsed && user.plan_type_unlinked == "Stripe"))
          upgraded = user.is_free?
          set_plan(user, active.plan_name)
        elsif active.nil? && apple_plan?(user)
          set_plan(user, "Free")
          downgraded = true
        end
      end

      # As a Stripe upgrade does: the email days a Free plan cut come back, and a thank-you.
      user.send_upgrade_email! if upgraded
      UserMailer.downgraded(user).deliver_later if downgraded
    end

    # A Stripe plan with a Stripe customer but no active or trialing Stripe subscription. Not
    # when Stripe can't be asked: the web plan stays, and the expiry check still applies.
    def lapsed_stripe_plan?(user)
      return false unless user.plan_type_unlinked == "Stripe" && user.stripe_id.present?

      user.has_active_stripe_subscription? == false
    rescue Stripe::StripeError => e
      Sentry.capture_exception(e, extra: { user_id: user.id, context: "AppStore::Entitlement.lapsed_stripe_plan?" })
      false
    end

    # Saved without validations: an account with, say, a legacy email that no longer passes
    # them must still get what it paid for. Callbacks still run (a downgrade revokes MCP tokens
    # and cuts the email days, as for Stripe).
    def set_plan(user, plan)
      return if user.plan == plan

      user.plan = plan
      user.save!(validate: false)
    end
  end
end
