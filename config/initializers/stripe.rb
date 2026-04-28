Stripe.api_key = ENV["STRIPE_API_KEY"]
StripeEvent.signing_secret = ENV["STRIPE_SIGNING_SECRET"]

StripeEvent.configure do |events|
  events.subscribe "checkout.session.completed" do |event|
    session = event.data.object
    if session.client_reference_id.present?
      user = User.where(id: session.client_reference_id).first
      if user.present?
        user.update(stripe_id: session.customer)
      end
    end
  end

  events.subscribe "invoice.payment_succeeded" do |event|
    invoice = event.data.object
    stripe_customer_id = invoice.customer
    line_item = event.data.object.lines.data.first
    paid = invoice.amount_paid.to_f / 100
    frequency = line_item.plan.interval == "month" ? "Monthly" : "Yearly"

    if stripe_customer_id.present?
      user = User.where(stripe_id: stripe_customer_id).first
      unless user
        user_id = line_item.metadata.dabble_id # look up user by dabble_id passed in during payment
        user ||= User.where(id: user_id).first
      end
      user ||= User.where(email: invoice.customer_email.downcase).first

      if user
        # Idempotent per invoice — same-day proration + subscription update are separate invoices.
        begin
          payment = user.payments.find_or_initialize_by(stripe_invoice_id: invoice.id)
          if payment.new_record?
            payment.assign_attributes(
              comments: "Stripe #{frequency} from #{invoice.customer_email}",
              date: Time.now.strftime('%Y-%m-%d').to_s,
              amount: paid
            )
            payment.save!
          end
        rescue ActiveRecord::RecordNotUnique
          # Concurrent duplicate webhook delivery
        end

        user.update(plan: "PRO #{frequency} PayHere")

        if user.plan_previous_change&.first == "Free"
          begin # upgrade happened, set frequency back + send thanks
            user.update(frequency: user.previous_frequency) if user.previous_frequency.any?
            UserMailer.thanks_for_paying(user).deliver_later
          rescue StandardError => e
            Sentry.set_user(id: user.id, email: user.email)
            Sentry.set_tags(plan: user.plan)
            Sentry.capture_exception(e)
          end
        end
      else
        UserMailer.no_user_here(invoice).deliver_later
      end
    end
  end

  events.subscribe "invoice.payment_failed" do |event|
    invoice = event.data.object
    stripe_customer_id = invoice.customer
    user = User.where(stripe_id: stripe_customer_id).first
    if user.present?
      Sentry.set_user(id: user.id, email: user.email)
      Sentry.set_tags(plan: user.plan)
    end
    Sentry.capture_message("Failed payment", level: :info, extra: { invoice: invoice })
  end

  # Update user.plan to match the current Stripe subscription's billing
  # interval. Fires on any subscription mutation — plan swap, trial end,
  # status change, cancel toggled, etc. — so we don't try to diff
  # `previous_attributes` (Stripe only delta-encodes what changed at the
  # root, and plan swaps rarely surface the old interval there). Instead
  # we read the current interval and set user.plan to match. Idempotent.
  events.subscribe "customer.subscription.updated" do |event|
    begin
      subscription = event.data.object
      stripe_customer_id = subscription.customer
      next if stripe_customer_id.blank?

      user = User.where(stripe_id: stripe_customer_id).first
      next unless user

      Sentry.set_user(id: user.id, email: user.email)
      Sentry.set_tags(plan: user.plan)

      if subscription.cancel_at_period_end
        Sentry.capture_message(
          "Customer set subscription to cancel at period end",
          level: :info,
          extra: { total_payments: user.payments.sum(:amount).to_f, subscription: subscription }
        )
        next
      end

      # Prefer the modern `items.data[0].price.recurring.interval` path (Stripe
      # API 2020-08-27+); fall back to the legacy `subscription.plan.interval`
      # alias for older API versions or back-compat objects.
      item = subscription.items&.data&.first
      interval = item&.price&.recurring&.interval ||
                 item&.plan&.interval ||
                 subscription.try(:plan)&.interval
      next if interval.blank?

      desired_plan =
        case interval.to_s.downcase
        when "year"  then "PRO Yearly PayHere"
        when "month" then "PRO Monthly PayHere"
        end

      user.update(plan: desired_plan) if desired_plan && user.plan != desired_plan
    rescue StandardError => e
      Sentry.capture_exception(e, extra: { event_id: event.id, subscription_id: subscription&.id })
    end
  end

  # Alert of cancellations
  events.subscribe "customer.subscription.deleted" do |event|
    subscription = event.data.object
    stripe_customer_id = subscription.customer
    if stripe_customer_id.present?
      user = User.where(stripe_id: stripe_customer_id).first
      if user.present? && !user.has_active_stripe_subscription?
        if subscription.cancellation_details&.reason == "payment_failed"
          user.update(plan: "Free")
          UserMailer.downgraded(user).deliver_now
        end

        Sentry.set_user(id: user.id, email: user.email)
        Sentry.set_tags(plan: user.plan)
        Sentry.capture_message("Subscription deleted", level: :info, extra: { total_payments: user.payments.sum(:amount).to_f, subscription: subscription })
      end
    end
  end
end
