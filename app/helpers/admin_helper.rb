module AdminHelper
  # Options for an admin plan dropdown. Always includes the user's current plan
  # and the selected value, so saving never silently swaps a legacy plan for
  # another one. "PayHere" plans are the Stripe ones, so their labels say so.
  def plan_options(current_plan, selected)
    plans = (User::SELECTABLE_PLANS + [current_plan, selected]).compact_blank.uniq
    options_for_select(plans.map { |p| [p.match?(/payhere/i) ? "#{p} (Stripe)" : p, p] }, selected)
  end

  # A Stripe Dashboard page, under /test when the app runs on a test key.
  def stripe_dashboard_url(path)
    test_mode = ENV["STRIPE_API_KEY"].to_s.match?(/\A(sk|rk)_test_/)
    "https://dashboard.stripe.com#{'/test' if test_mode}/#{path}"
  end

  # Where to look a payment up: its Stripe invoice, else the provider named in
  # the comment the webhook wrote ("Gumroad Monthly from ..."), else the user's
  # Stripe customer. Returns [label, url], or nil for a manual payment with
  # nothing to link to.
  def payment_source(payment)
    return ["Stripe invoice", stripe_dashboard_url("invoices/#{payment.stripe_invoice_id}")] if payment.stripe_invoice_id.present?

    stripe_customer = ["Stripe customer", stripe_dashboard_url("customers/#{payment.user.stripe_id}")] if payment.user&.stripe_id.present?
    case payment.comments.to_s
    when /\AStripe /i then stripe_customer || ["Stripe", stripe_dashboard_url("payments")]
    when /\AGumroad /i then ["Gumroad", "https://app.gumroad.com/customers"]
    when /\APayHere /i then ["PayHere", "https://app.payhere.co"]
    when /\APaypal /i then ["PayPal", "https://www.paypal.com/myaccount/activities"]
    else stripe_customer
    end
  end
end
