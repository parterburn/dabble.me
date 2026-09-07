# frozen_string_literal: true

# One-off: confirm overdue PRO renewals (the "3 monthly / 51 yearly" claim).
#
# Production console:
#   load Rails.root.join('script/investigate_overdue_renewals.rb')
#   OverdueRenewals.report            # local DB only
#   OverdueRenewals.report(stripe: true)  # also compare Stripe invoices (slower)
#
# Read-only. Leaves OVERDUE_YEARLY / OVERDUE_MONTHLY in the console.

module OverdueRenewals
  YEARLY_MIN = 7.00
  MONTHLY_MIN = 1.00
  YEARLY_RENEWAL = 365.days
  YEARLY_DOWNGRADE = 375.days
  YEARLY_STATS = RevenueMetrics::YEARLY_AT_RISK_AFTER_DAYS.days # 380
  YEARLY_OLD_STATS = 340.days
  MONTHLY_RENEWAL = 30.days
  MONTHLY_DOWNGRADE = 40.days
  MONTHLY_STATS = RevenueMetrics::MONTHLY_AT_RISK_AFTER_DAYS.days # 45
  MONTHLY_OLD_STATS = 32.days

  module_function

  def report(stripe: false)
    puts "\n#{'=' * 72}"
    puts "Overdue renewals as of #{Time.current.xmlschema} (#{Time.zone})"
    puts '=' * 72

    print_counts
    yearly = load_users(yearly_ids(YEARLY_STATS), YEARLY_MIN)
    monthly = load_users(monthly_ids(MONTHLY_STATS), MONTHLY_MIN)

    print_groupings(yearly, 'YEARLY (stats page: last qualifying pay > 380d / 15 days past due)')
    print_rows(yearly, 'yearly')

    puts "\n--- Monthly (#{monthly.size}; stats page: last qualifying pay > 45d) ---"
    print_rows(monthly, 'monthly')

    if stripe
      puts "\nHitting Stripe for #{yearly.size} yearly users..."
      enrich_stripe!(yearly)
      print_stripe_summary(yearly)
      print_rows(yearly, 'yearly', stripe: true)
    else
      puts "\nSkip Stripe. Re-run with OverdueRenewals.report(stripe: true) to compare invoices."
    end

    Object.send(:remove_const, :OVERDUE_YEARLY) if Object.const_defined?(:OVERDUE_YEARLY)
    Object.send(:remove_const, :OVERDUE_MONTHLY) if Object.const_defined?(:OVERDUE_MONTHLY)
    Object.const_set(:OVERDUE_YEARLY, yearly)
    Object.const_set(:OVERDUE_MONTHLY, monthly)

    puts "\nDone. Arrays: OVERDUE_YEARLY (#{yearly.size}), OVERDUE_MONTHLY (#{monthly.size})"
    nil
  end

  def metrics_at_risk
    RevenueMetrics.current.at_risk
  end

  def old_metrics_at_risk
    metrics = RevenueMetrics.current
    monthly = metrics.recurring.select do |s|
      s.interval == :monthly && s.last_paid_on.present? && s.last_paid_on.to_date < Date.current - MONTHLY_OLD_STATS
    end
    yearly = metrics.recurring.select do |s|
      s.interval == :yearly && s.last_paid_on.present? && s.last_paid_on.to_date < Date.current - YEARLY_OLD_STATS
    end
    { monthly_count: monthly.size, yearly_count: yearly.size }
  end

  def print_counts
    y_pro = User.pro_only.yearly.count
    y_nf = User.pro_only.yearly.not_forever.count
    y_nf_alive = User.pro_only.yearly.not_forever.not_deleted.count
    m_pro = User.pro_only.monthly.count
    current_risk = metrics_at_risk
    old_risk = old_metrics_at_risk

    puts <<~COUNTS

      Universe
        PRO yearly:                    #{y_pro}
        PRO yearly not-forever:        #{y_nf}  (not deleted: #{y_nf_alive})
        PRO monthly:                   #{m_pro}

      Stats page (RevenueMetrics#at_risk — latest payment, any amount)
        current (45d monthly / 380d yearly):               #{current_risk[:monthly_count]} / #{current_risk[:yearly_count]}
        old cutoff that produced ~50 (32d / 340d):         #{old_risk[:monthly_count]} / #{old_risk[:yearly_count]}

      Yearly — same query shape as UserDowngradeExpiredWorker
        last amt>$7 pay older than 365d (renewal due):     #{yearly_ids(YEARLY_RENEWAL).size}
        last amt>$7 pay older than 375d (downgrade due):   #{yearly_ids(YEARLY_DOWNGRADE).size}
        last amt>$7 pay older than 380d (stats page):      #{yearly_ids(YEARLY_STATS).size}
        last pay (any amount) older than 365d:             #{yearly_ids_any_amount(YEARLY_RENEWAL).size}
        no qualifying amt>$7 payments at all:              #{yearly_no_qualifying_ids.size}
        payments.last by id (not date) older than 365d:    #{yearly_last_by_id_count}

      Monthly
        last amt>$1 pay older than 30d (renewal due):      #{monthly_ids(MONTHLY_RENEWAL).size}
        last amt>$1 pay older than 40d (downgrade due):    #{monthly_ids(MONTHLY_DOWNGRADE).size}
        last amt>$1 pay older than 45d (stats page):       #{monthly_ids(MONTHLY_STATS).size}

    COUNTS
  end

  def yearly_scope(older_than, min_amount = YEARLY_MIN)
    User.pro_only.yearly.not_forever.joins(:payments)
        .where('payments.amount > ?', min_amount)
        .having('MAX(payments.date) < ?', older_than.ago)
        .group('users.id')
  end

  def monthly_scope(older_than)
    User.pro_only.monthly.not_forever.joins(:payments)
        .where('payments.amount > ?', MONTHLY_MIN)
        .having('MAX(payments.date) < ?', older_than.ago)
        .group('users.id')
  end

  def yearly_ids(older_than)
    yearly_scope(older_than).pluck('users.id')
  end

  def monthly_ids(older_than)
    monthly_scope(older_than).pluck('users.id')
  end

  def yearly_ids_any_amount(older_than)
    User.pro_only.yearly.not_forever.joins(:payments)
        .having('MAX(payments.date) < ?', older_than.ago)
        .group('users.id')
        .pluck('users.id')
  end

  def yearly_no_qualifying_ids
    User.pro_only.yearly.not_forever
        .where.not(id: User.pro_only.yearly.not_forever.joins(:payments)
                           .where('payments.amount > ?', YEARLY_MIN)
                           .select('users.id'))
        .pluck(:id)
  end

  # Admin pages use user.payments.last (primary key), not MAX(date).
  def yearly_last_by_id_count
    User.pro_only.yearly.not_forever.includes(:payments).count do |user|
      pay = user.payments.max_by(&:id)
      pay&.date && pay.date < YEARLY_RENEWAL.ago
    end
  end

  def load_users(ids, min_amount)
    User.where(id: ids).includes(:payments).map { |user| decorate(user, min_amount) }
        .sort_by { |row| [row[:days_since] || -1, row[:id]] }
        .reverse
  end

  def decorate(user, min_amount)
    qualifying = user.payments.select { |p| p.amount.to_f > min_amount }.max_by { |p| [p.date, p.id] }
    last_any = user.payments.max_by { |p| [p.date, p.id] }
    last_by_id = user.payments.max_by(&:id)

    {
      id: user.id,
      email: user.email,
      plan: user.plan,
      deleted: user.deleted_at.present?,
      stripe_id: user.stripe_id,
      gumroad_id: user.gumroad_id,
      payhere_id: user.payhere_id,
      payment_count: user.payments.size,
      qualifying: qualifying,
      last_any: last_any,
      last_by_id: last_by_id,
      days_since: qualifying ? ((Time.current - qualifying.date) / 1.day).floor : nil,
      pay_years: user.payments.map { |p| p.date&.year }.compact.uniq.sort,
      provider: provider_for(user, qualifying || last_any),
      user: user
    }
  end

  def provider_for(user, payment)
    blob = [user.plan, payment&.comments].join(' ')
    return 'Stripe' if user.stripe_id.present? || blob.match?(/stripe|payhere/i)
    return 'Gumroad' if user.gumroad_id.present? || blob.match?(/gumroad/i)
    return 'PayPal' if blob.match?(/paypal/i)

    'Unknown'
  end

  def print_groupings(rows, title)
    puts "\n#{title}: #{rows.size}"
    return if rows.empty?

    puts "  by plan:      #{rows.map { |r| r[:plan] }.tally.sort_by(&:last).reverse.to_h}"
    puts "  by provider:  #{rows.map { |r| r[:provider] }.tally}"
    puts "  deleted:      #{rows.count { |r| r[:deleted] }}"
    puts "  has stripe_id: #{rows.count { |r| r[:stripe_id].present? }}"
    puts "  has gumroad_id: #{rows.count { |r| r[:gumroad_id].present? }}"
    buckets = rows.group_by { |r| day_bucket(r[:days_since]) }.transform_values(&:size)
    puts "  days since last qualifying pay: #{buckets.sort.to_h}"
  end

  def day_bucket(days)
    return 'none' if days.nil?
    return '365-374 (renewal, not yet downgrade)' if days < 375
    return '375-399' if days < 400
    return '400-729 (~1-2y)' if days < 730
    return '730-1094 (~2-3y)' if days < 1095

    '1095+ (3y+)'
  end

  def print_rows(rows, kind, stripe: false)
    return if rows.empty?

    rows.each_with_index do |row, i|
      q = row[:qualifying]
      any = row[:last_any]
      puts format(
        '%2d. id=%-6s %-36s  %s%s',
        i + 1,
        row[:id],
        row[:email].to_s[0, 36],
        row[:plan],
        row[:deleted] ? '  [DELETED]' : ''
      )
      if q
        puts format(
          '    last qualifying: %s  $%s  %sd ago  %s  invoice=%s',
          q.date&.to_date,
          q.amount,
          row[:days_since],
          q.comments.to_s[0, 60],
          q.stripe_invoice_id.presence || '-'
        )
      else
        puts '    last qualifying: NONE'
      end
      if any && any != q
        puts format(
          '    last any-amount: %s  $%s  %s',
          any.date&.to_date,
          any.amount,
          any.comments.to_s[0, 60]
        )
      end
      if row[:last_by_id] && q && row[:last_by_id].id != q.id
        puts "    NOTE payments.last (by id) != MAX(date): id=#{row[:last_by_id].id} date=#{row[:last_by_id].date&.to_date}"
      end
      puts format(
        '    pays=%s years=%s stripe_id=%s gumroad_id=%s payhere_id=%s',
        row[:payment_count],
        row[:pay_years].join(',')[0, 40],
        row[:stripe_id].presence || '-',
        row[:gumroad_id].presence || '-',
        row[:payhere_id].presence || '-'
      )
      next unless stripe && kind == 'yearly'

      s = row[:stripe]
      if s.nil?
        puts '    stripe: (no stripe_id)'
      elsif s[:error]
        puts "    stripe: ERROR #{s[:error]}"
      else
        puts format(
          '    stripe: %s interval=%s period_end=%s cancel_at_end=%s',
          s[:statuses].presence || 'no subscriptions',
          s[:interval] || '-',
          s[:period_end] || '-',
          s[:cancel_at_period_end]
        )
        if s[:latest_paid]
          flag = s[:missing_local] ? '  *** NOT IN LOCAL PAYMENTS ***' : ''
          puts format(
            '    stripe latest paid: %s %s $%s%s',
            s[:latest_paid][:id],
            s[:latest_paid][:date],
            s[:latest_paid][:amount],
            flag
          )
        else
          puts '    stripe latest paid: none'
        end
      end
    end
  end

  def enrich_stripe!(rows)
    rows.each_with_index do |row, i|
      next if row[:stripe_id].blank?

      print "  Stripe #{i + 1}/#{rows.size} id=#{row[:id]}\r"
      row[:stripe] = fetch_stripe(row)
    rescue Stripe::StripeError => e
      row[:stripe] = { error: "#{e.class}: #{e.message}" }
    end
    puts
  end

  def fetch_stripe(row)
    subs = Stripe::Subscription.list(customer: row[:stripe_id], status: 'all', limit: 10).data
    invoices = Stripe::Invoice.list(customer: row[:stripe_id], limit: 8, status: 'paid').data
    latest = invoices.max_by { |inv| inv.status_transitions&.paid_at || inv.created || 0 }
    local_ids = row[:user].payments.map(&:stripe_invoice_id).compact
    latest_date = invoice_date(latest)
    missing = if latest
                local_ids.exclude?(latest.id) &&
                  (row[:qualifying].nil? || (latest_date && latest_date.to_date > row[:qualifying].date.to_date))
              else
                false
              end

    interesting = subs.select { |s| %w[trialing active past_due unpaid incomplete].include?(s.status) }
    pick = interesting.first || subs.first

    {
      statuses: subs.map { |s| "#{s.status}(#{s.id})" },
      interval: subscription_interval(pick),
      period_end: format_ts(subscription_period_end(pick)),
      cancel_at_period_end: pick&.cancel_at_period_end,
      latest_paid: latest && {
        id: latest.id,
        date: latest_date,
        amount: format('%.2f', latest.amount_paid.to_f / 100)
      },
      missing_local: missing
    }
  end

  def subscription_interval(sub)
    return if sub.nil?

    item = sub.items&.data&.first
    item&.price&.recurring&.interval || item&.plan&.interval || sub.try(:plan)&.interval
  end

  def subscription_period_end(sub)
    return if sub.nil?

    item = sub.items&.data&.first
    item.try(:current_period_end) || sub.try(:current_period_end)
  end

  def invoice_date(invoice)
    return if invoice.nil?

    ts = invoice.status_transitions&.paid_at || invoice.created
    Time.zone.at(ts).to_date if ts
  end

  def format_ts(ts)
    ts ? Time.zone.at(ts).to_date : nil
  end

  def print_stripe_summary(rows)
    checked = rows.select { |r| r[:stripe] }
    errors = checked.select { |r| r.dig(:stripe, :error) }
    missing = checked.select { |r| r.dig(:stripe, :missing_local) }
    active = checked.select do |r|
      Array(r.dig(:stripe, :statuses)).any? { |s| s.start_with?('active', 'trialing') }
    end
    puts "\nStripe vs local (#{checked.size} customers, #{errors.size} errors)"
    puts "  active/trialing on Stripe:          #{active.size}"
    puts "  Stripe paid invoice not in Dabble:  #{missing.size}"
    missing.each do |r|
      inv = r.dig(:stripe, :latest_paid)
      puts "    id=#{r[:id]} #{r[:email]}  stripe #{inv&.dig(:id)} #{inv&.dig(:date)} $#{inv&.dig(:amount)}"
    end
  end
end

puts "Loaded OverdueRenewals. Run: OverdueRenewals.report   or   OverdueRenewals.report(stripe: true)"
