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
        if user.payments.where("comments ILIKE '%#{frequency}%'").last&.date&.to_date != Date.today
          Payment.create(user_id: user.id, comments: "Stripe #{frequency} from #{invoice.customer_email}", date: Time.now.strftime("%Y-%m-%d").to_s, amount: paid)
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

  # Update plan when a user changes it
  events.subscribe "customer.subscription.updated" do |event|
    subscription = event.data.object
    stripe_customer_id = subscription.customer
    if stripe_customer_id.present?
      user = User.where(stripe_id: stripe_customer_id).first
      if user.present?
        cancel_at_period_end = subscription.cancel_at_period_end

        if cancel_at_period_end
          if user.present?
            Sentry.set_user(id: user.id, email: user.email)
            Sentry.set_tags(plan: user.plan)
          end
          Sentry.capture_message("Customer set subscription to cancel at period end", level: :info, extra: { total_payments: user.payments.sum(:amount).to_f, subscription: subscription })
        else
          previous_attributes = event.data.previous_attributes
          if previous_attributes && previous_attributes['items']
            old_plan = previous_attributes['items']['data'][0]['plan']['interval']
            new_plan = subscription.plan.interval

            # user changed plans, ajust accordingly
            if old_plan && new_plan && old_plan != new_plan
              if new_plan.downcase.include?("year")
                user.update(plan: "PRO Yearly PayHere")
              elsif new_plan.downcase.include?("month")
                user.update(plan: "PRO Monthly PayHere")
              end
            end
          end
        end
      end
    end
  end

  # Alert of cancellations
  events.subscribe "customer.subscription.deleted" do |event|
    subscription = event.data.object
    stripe_customer_id = subscription.customer
      if stripe_customer_id.present?
      user = User.where(stripe_id: stripe_customer_id).first
      if user.present?
        Sentry.set_user(id: user.id, email: user.email)
        Sentry.set_tags(plan: user.plan)
        Sentry.capture_message("Subscription deleted", level: :info, extra: { total_payments: user.payments.sum(:amount).to_f, subscription: subscription })
      end
    end
  end
end
