Stripe.api_key = ENV["STRIPE_API_KEY"]
StripeEvent.signing_secret = ENV["STRIPE_SIGNING_SECRET"]

StripeEvent.configure do |events|
  events.subscribe "checkout.session.completed" do |event|
    session = event.data.object
    user = User.where(id: session.client_reference_id).first
    return nil unless user

    user.update(stripe_id: session.customer)
  end

  events.subscribe "invoice.payment_succeeded" do |event|
    invoice = event.data.object
    stripe_customer_id = invoice.customer
    line_item = event.data.object.lines.data.first
    paid = invoice.amount_paid.to_f / 100
    frequency = line_item.plan.interval == "month" ? "Monthly" : "Yearly"
    user = User.where(stripe_id: stripe_customer_id).first
    unless user
      user_id = line_item.metadata.dabble_id # look up user by dabble_id passed in during payment
      user = User.where(id: user_id).first unless user
    end
    user = User.where(email: invoice.customer_email.downcase).first unless user

    if user
      if user.payments.where("comments ILIKE '%#{frequency}%'").last&.date&.to_date != Date.today
        Payment.create(user_id: user.id, comments: "Stripe #{frequency} from #{invoice.customer_email}", date: "#{Time.now.strftime("%Y-%m-%d")}", amount: paid)
      end
      user.update(plan: "PRO #{frequency} PayHere", stripe_id: stripe_customer_id)
    end
  end

  events.subscribe "invoice.payment_failed" do |event|
    invoice = event.data.object
    stripe_customer_id = invoice.customer
    user = User.where(stripe_id: stripe_customer_id).first

    Sentry.capture_message("Failed payment", level: :info, extra: { user_id: user&.id, user_email: user&.email, invoice: invoice })
  end

  # Update plan when a user changes it
  events.subscribe "customer.subscription.updated" do |event|
    subscription = event.data.object
    stripe_customer_id = subscription.customer
    user = User.where(stripe_id: stripe_customer_id).first
    return nil unless user

    cancel_at_period_end = subscription.cancel_at_period_end

    if cancel_at_period_end
      p "*"*100
      p "cancel_at_period_end"
      p "*"*100
      Sentry.capture_message("Customer set subscription to cancel at period end", level: :info, extra: { user_id: user.id, user_email: user.email, total_payments: user.payments.sum(:amount).to_f, subscription: subscription })
    else
      previous_attributes = event.data.previous_attributes
      if previous_attributes && previous_attributes['items']
        old_plan = previous_attributes['items']['data'][0]['plan']['interval']
        new_plan = subscription.plan.interval

        # user changed plans, ajust accordingly
        if old_plan && new_plan && old_plan != new_plan
          if new_plan.include?("year")
            user.update(plan: "PRO Yearly PayHere")
          elsif new_plan.include?("month")
            user.update(plan: "PRO Monthly PayHere")
          end
        end
      end
    end
  end

  # Alert of cancellations
  events.subscribe "customer.subscription.deleted" do |event|
    subscription = event.data.object
    stripe_customer_id = subscription.customer
    user = User.where(stripe_id: stripe_customer_id).first
    return nil unless user

    Sentry.capture_message("Subscription deleted", level: :info, extra: { user_id: user.id, user_email: user.email, total_payments: user.payments.sum(:amount).to_f, subscription: subscription })
  end
end
