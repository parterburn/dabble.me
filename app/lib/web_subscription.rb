# frozen_string_literal: true

# When a PRO plan bought on dabble.me renews, or ends, for the app's Plan page
# (GET /api/v1/plan). Only Stripe knows, so only Stripe plans have one: Gumroad and PayPal bill
# on their own, and PRO Forever doesn't renew. Stripe's answer is cached for CACHE_FOR; a
# change made in Stripe's billing portal shows up once it runs out.
module WebSubscription
  CACHE_FOR = 6.hours

  module_function

  # { provider: "Stripe", expires_at:, will_renew: } or nil.
  def for(user)
    return nil unless user.is_pro? && user.plan_type_unlinked == "Stripe" && user.stripe_id.present?

    Rails.cache.fetch(["web_subscription", user.id, user.stripe_id, user.plan], expires_in: CACHE_FOR, skip_nil: true) do
      from_stripe(user.stripe_id)
    end
  end

  def from_stripe(customer_id)
    subscription = Stripe::Subscription.list(customer: customer_id, limit: 10).data
                                       .select { |s| %w[active trialing past_due].include?(s.status) }
                                       .max_by { |s| period_end(s).to_i }
    ends = subscription && period_end(subscription)
    return nil unless ends

    # Cancelled in the billing portal: it runs to the end of the period, then stops.
    will_renew = !subscription.cancel_at_period_end && subscription.cancel_at.blank?
    { provider: "Stripe", expires_at: Time.at(subscription.cancel_at || ends).utc, will_renew: will_renew }
  rescue Stripe::StripeError => e
    Sentry.capture_exception(e, level: :warning, extra: { stripe_customer: customer_id })
    nil
  end

  # Newer Stripe API versions keep the period on the subscription's items.
  def period_end(subscription)
    item = subscription.respond_to?(:items) && subscription.items&.data&.first
    (item.respond_to?(:current_period_end) && item.current_period_end) ||
      (subscription.respond_to?(:current_period_end) && subscription.current_period_end) || nil
  end
end
