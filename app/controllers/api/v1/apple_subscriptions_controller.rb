# frozen_string_literal: true

module Api
  module V1
    # The iOS app's in-app purchase, restore and renewal updates: StoreKit's signed transaction
    # (Transaction.jwsRepresentation), which AppStore::Subscriptions verifies and checks against
    # Apple before the account's plan changes. The app finishes the transaction once this
    # answers 200, or with one of the refusals below, which retrying won't change.
    class AppleSubscriptionsController < BaseController
      # POST /api/v1/apple_subscriptions {signed_transaction}
      def create
        signed = params[:signed_transaction]
        unless signed.is_a?(String) && signed.bytesize < 32.kilobytes
          return render_error(:unprocessable_content, 'invalid_transaction', 'That purchase could not be read.')
        end

        AppStore::Subscriptions.claim!(user: current_user, signed_transaction: signed)
        render json: self.class.status_json(current_user.reload)
      rescue AppStore::Subscriptions::OtherAccount => e
        render_error(:conflict, 'subscription_belongs_to_other_account',
                     "This App Store subscription is already linked to another Dabble Me account (#{AppStore.mask_email(e.owner.email)}). " \
                     "Sign in to that account to use it, or email hello@dabble.me for help.")
      rescue AppStore::Subscriptions::FamilyShared
        render_error(:unprocessable_content, 'family_sharing_not_supported',
                     "Dabble Me PRO isn't shared through Family Sharing. Subscribe from your own Apple Account to get PRO.")
      rescue AppStore::VerificationError => e
        Sentry.capture_message('Apple transaction refused', level: :warning, extra: { reason: e.message })
        render_error(:unprocessable_content, 'invalid_transaction', 'That purchase could not be verified.')
      end

      # What /api/v1/me says about the plan, after a purchase.
      def self.status_json(user)
        subscription = AppStore::Entitlement.active_subscription(user)
        {
          plan: user.is_pro? ? 'pro' : 'free',
          is_pro: user.is_pro?,
          pro_source: pro_source(user),
          apple_subscription: subscription && {
            product_id: subscription.product_id,
            expires_at: subscription.expires_at&.iso8601,
            will_renew: subscription.auto_renew,
            in_grace_period: subscription.in_grace_period?,
            sandbox: subscription.sandbox?
          }
        }
      end

      # "apple" when the App Store subscription is what makes the account PRO, "web" when
      # something else does (Stripe, Gumroad, PayPal, Forever, or set by hand), nil when Free.
      def self.pro_source(user)
        return nil unless user.is_pro?

        AppStore::Entitlement.apple_plan?(user) ? 'apple' : 'web'
      end
    end
  end
end
