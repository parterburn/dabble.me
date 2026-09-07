# frozen_string_literal: true

# Point-in-time recurring revenue from current `users.plan` plus each
# subscriber's latest payment. This is not a subscription ledger: when a
# user churns, historical MRR cannot be reconstructed — that is why
# BusinessMetricSnapshot exists.
class RevenueMetrics
  Subscriber = Struct.new(
    :user_id,
    :plan,
    :referrer,
    :created_at,
    :amount_cents,
    :last_paid_on,
    :interval,
    :cohort,
    keyword_init: true
  )

  TARGET_ARR_CENTS = 2_000_000 # $20,000
  ANNUAL_EQUIVALENT_CENTS = 4_000 # public $40/year
  MONTHLY_LEGACY_MAX_CENTS = 350 # $3.00 vs $4.00
  YEARLY_LEGACY_MAX_CENTS = 3_500 # $30.00 vs $40.00
  # Stripe auto-charges on the anniversary and retries failed payments for
  # several days. Only surface a subscriber once they are more than 15 days
  # past the expected renewal (30 + 15 monthly, 365 + 15 yearly).
  AT_RISK_GRACE_DAYS = 15
  MONTHLY_PERIOD_DAYS = 30
  YEARLY_PERIOD_DAYS = 365
  MONTHLY_AT_RISK_AFTER_DAYS = MONTHLY_PERIOD_DAYS + AT_RISK_GRACE_DAYS
  YEARLY_AT_RISK_AFTER_DAYS = YEARLY_PERIOD_DAYS + AT_RISK_GRACE_DAYS
  COHORT_KEYS = %w[
    legacy_monthly
    new_monthly
    unknown_monthly
    legacy_yearly
    new_yearly
    unknown_yearly
    lifetime
  ].freeze

  class << self
    def current(as_of: Time.current)
      new(as_of: as_of)
    end
  end

  attr_reader :as_of, :subscribers

  def initialize(as_of: Time.current)
    @as_of = as_of
    @subscribers = load_subscribers
  end

  def recurring
    @recurring ||= subscribers.reject { |s| s.interval == :lifetime }
  end

  def lifetime
    @lifetime ||= subscribers.select { |s| s.interval == :lifetime }
  end

  def mrr_cents
    @mrr_cents ||= recurring.sum { |s| mrr_cents_for(s) }
  end

  def arr_cents
    @arr_cents ||= recurring.sum { |s| arr_cents_for(s) }
  end

  def recurring_subscriber_count
    recurring.size
  end

  def lifetime_subscriber_count
    lifetime.size
  end

  def monthly_count
    recurring.count { |s| s.interval == :monthly }
  end

  def yearly_count
    recurring.count { |s| s.interval == :yearly }
  end

  def monthly_cash_cents
    recurring.select { |s| s.interval == :monthly }.sum { |s| s.amount_cents.to_i }
  end

  def yearly_cash_cents
    recurring.select { |s| s.interval == :yearly }.sum { |s| s.amount_cents.to_i }
  end

  def plan_breakdown
    COHORT_KEYS.index_with do |key|
      group = subscribers.select { |s| s.cohort == key }
      {
        "count" => group.size,
        "mrr_cents" => group.sum { |s| mrr_cents_for(s) },
        "arr_cents" => group.sum { |s| arr_cents_for(s) }
      }
    end
  end

  def subscriber_map
    recurring.each_with_object({}) do |subscriber, memo|
      memo[subscriber.user_id.to_s] = {
        "c" => subscriber.cohort,
        "m" => mrr_cents_for(subscriber)
      }
    end
  end

  def mrr_cents_for(subscriber)
    return 0 if subscriber.interval == :lifetime

    amount = subscriber.amount_cents.to_i
    case subscriber.interval
    when :yearly
      (amount / 12.0).round
    else
      amount
    end
  end

  def arr_cents_for(subscriber)
    return 0 if subscriber.interval == :lifetime

    amount = subscriber.amount_cents.to_i
    case subscriber.interval
    when :yearly
      amount
    else
      amount * 12
    end
  end

  def at_risk(as_of_date: as_of.to_date)
    monthly_risk = recurring.select do |s|
      past_due_renewal?(s, :monthly, as_of_date)
    end
    yearly_risk = recurring.select do |s|
      past_due_renewal?(s, :yearly, as_of_date)
    end
    {
      monthly_count: monthly_risk.size,
      yearly_count: yearly_risk.size,
      mrr_cents: (monthly_risk + yearly_risk).sum { |s| mrr_cents_for(s) }
    }
  end

  def upcoming_annual_renewals(within: 30.days, as_of_date: as_of.to_date)
    window_end = as_of_date + within
    recurring.select do |s|
      next false unless s.interval == :yearly && s.last_paid_on.present?

      renewal_on = s.last_paid_on.to_date + 1.year
      renewal_on >= as_of_date && renewal_on <= window_end
    end
  end

  def classify(plan:, amount_cents:)
    plan_text = plan.to_s
    interval = interval_for(plan_text, amount_cents)
    cohort = cohort_for(interval, amount_cents)
    [interval, cohort]
  end

  private

  def load_subscribers
    pro_users = User.not_deleted.pro_only.select(:id, :plan, :referrer, :created_at).to_a
    return [] if pro_users.empty?

    latest_by_user_id = latest_payments_by_user_id(pro_users.map(&:id))

    pro_users.map do |user|
      payment = latest_by_user_id[user.id]
      amount_cents = payment ? dollars_to_cents(payment.amount) : 0
      last_paid_on = payment&.date
      interval, cohort = classify(plan: user.plan, amount_cents: amount_cents)

      Subscriber.new(
        user_id: user.id,
        plan: user.plan,
        referrer: user.referrer,
        created_at: user.created_at,
        amount_cents: amount_cents,
        last_paid_on: last_paid_on,
        interval: interval,
        cohort: cohort
      )
    end
  end

  def latest_payments_by_user_id(user_ids)
    return {} if user_ids.empty?

    payments = Payment.find_by_sql([
      <<~SQL.squish,
        SELECT DISTINCT ON (user_id) user_id, amount, date
        FROM payments
        WHERE user_id IN (?)
          AND date <= ?
        ORDER BY user_id, date DESC, id DESC
      SQL
      user_ids,
      as_of
    ])
    payments.index_by(&:user_id)
  end

  def interval_for(plan, amount_cents)
    return :lifetime if plan.match?(/forever/i)
    return :monthly if plan.match?(/monthly/i)
    return :yearly if plan.match?(/yearly/i)

    if amount_cents.to_i > 1_000
      :yearly
    elsif amount_cents.to_i.positive?
      :monthly
    else
      :lifetime
    end
  end

  def cohort_for(interval, amount_cents)
    cents = amount_cents.to_i
    case interval
    when :lifetime
      "lifetime"
    when :monthly
      return "unknown_monthly" if cents <= 0
      cents < MONTHLY_LEGACY_MAX_CENTS ? "legacy_monthly" : "new_monthly"
    when :yearly
      return "unknown_yearly" if cents <= 0
      cents < YEARLY_LEGACY_MAX_CENTS ? "legacy_yearly" : "new_yearly"
    else
      "unknown_monthly"
    end
  end

  def dollars_to_cents(amount)
    (BigDecimal(amount.to_s) * 100).round
  end

  def past_due_renewal?(subscriber, interval, as_of_date)
    return false unless subscriber.interval == interval && subscriber.last_paid_on.present?

    grace_after = as_of_date - at_risk_after_days(interval).days
    subscriber.last_paid_on.to_date < grace_after
  end

  def at_risk_after_days(interval)
    interval == :yearly ? YEARLY_AT_RISK_AFTER_DAYS : MONTHLY_AT_RISK_AFTER_DAYS
  end
end
