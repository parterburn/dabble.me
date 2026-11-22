# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/plan: the app's Plan page. What /api/v1/me says about the plan, and when a
    # plan bought on dabble.me renews (WebSubscription). Kept out of /me, which the app loads
    # at every launch, because it may ask Stripe.
    class PlansController < BaseController
      def show
        web = AppleSubscriptionsController.pro_source(current_user) == 'web' && WebSubscription.for(current_user)
        render json: AppleSubscriptionsController.status_json(current_user).merge(
          web_subscription: web.presence && {
            provider: web[:provider],
            expires_at: web[:expires_at].iso8601,
            will_renew: web[:will_renew]
          }
        )
      end
    end
  end
end
