# frozen_string_literal: true

module Admin
  class Dashboard
    TARGET_ARR_CENTS = RevenueMetrics::TARGET_ARR_CENTS
    ANNUAL_EQUIVALENT_CENTS = RevenueMetrics::ANNUAL_EQUIVALENT_CENTS
    COHORT_LABELS = {
      "legacy_monthly" => "Legacy monthly ($3)",
      "new_monthly" => "New monthly ($4)",
      "unknown_monthly" => "Monthly (unknown price)",
      "legacy_yearly" => "Legacy yearly ($30)",
      "new_yearly" => "New yearly ($40)",
      "unknown_yearly" => "Yearly (unknown price)",
      "lifetime" => "Lifetime (excluded from MRR)"
    }.freeze
    FUNNEL_LABELS = {
      "signups" => "Signed up",
      "prompted" => "Received a prompt",
      "wrote" => "Wrote a first entry",
      "wrote_72h" => "First entry within 72 hours",
      "upgraded" => "Currently PRO"
    }.freeze

    attr_reader :now, :as_of, :revenue

    def initialize(now: Time.current)
      @now = now
      @as_of = now
      @revenue = RevenueMetrics.current(as_of: now)
    end

    def latest_snapshot
      @latest_snapshot ||= BusinessMetricSnapshot.order(captured_on: :desc).first
    end

    def yesterday_snapshot
      @yesterday_snapshot ||= BusinessMetricSnapshot.find_by(captured_on: as_of.to_date - 1.day)
    end

    def week_ago_snapshot
      @week_ago_snapshot ||= snapshot_on_or_before(as_of.to_date - 7.days)
    end

    def month_start_snapshot
      @month_start_snapshot ||= snapshot_on_or_before(as_of.to_date.beginning_of_month)
    end

    def snapshot_count
      @snapshot_count ||= BusinessMetricSnapshot.count
    end

    def attention_items
      items = []

      if latest_snapshot && latest_snapshot.churned_mrr_cents > latest_snapshot.gross_new_mrr_cents
        items << "Churned MRR exceeded new MRR on the latest snapshot."
      end

      if comparable_snapshots?
        if rate_fell?(:first_entry_activation_rate)
          items << "72-hour first-entry activation fell versus last week."
        end
        if rate_fell?(:email_reply_rate)
          items << "Email reply rate fell versus last week."
        end
        if latest_snapshot.paid_inactive_30d > week_ago_snapshot.paid_inactive_30d
          items << "PRO inactivity rose versus last week (#{week_ago_snapshot.paid_inactive_30d} → #{latest_snapshot.paid_inactive_30d} with no entry in 30 days)."
        end
      end

      at_risk = revenue.at_risk
      if at_risk[:monthly_count].positive? || at_risk[:yearly_count].positive?
        items << "#{at_risk[:monthly_count]} monthly and #{at_risk[:yearly_count]} yearly subscribers look overdue for a renewal payment."
      end

      gap = TARGET_ARR_CENTS - revenue.arr_cents
      items << "ARR is #{format_cents(gap)} below the $20k target." if gap.positive?

      items.first(3)
    end

    def headline_item
      attention_items.first || "No urgent metric this week. Keep shipping activation and retention."
    end

    def mrr_delta_cents
      return unless yesterday_snapshot

      revenue.mrr_cents - yesterday_snapshot.mrr_cents
    end

    def arr_delta_week_cents
      return unless week_ago_snapshot

      revenue.arr_cents - week_ago_snapshot.arr_cents
    end

    def arr_delta_month_cents
      return unless month_start_snapshot

      revenue.arr_cents - month_start_snapshot.arr_cents
    end

    def net_new_mrr_cents
      return unless latest_snapshot

      latest_snapshot.net_new_mrr_cents
    end

    def month_net_arr_cents
      arr_delta_month_cents
    end

    def month_annual_equivalent
      delta = month_net_arr_cents
      return unless delta

      (delta.to_f / ANNUAL_EQUIVALENT_CENTS).round(1)
    end

    def arr_progress_percent
      ((revenue.arr_cents.to_f / TARGET_ARR_CENTS) * 100).round(1)
    end

    def pricing_cohorts
      revenue.plan_breakdown.map do |key, data|
        next unless COHORT_LABELS.key?(key)
        next if data["count"].to_i.zero? && key.start_with?("unknown", "lifetime")

        {
          key: key,
          label: COHORT_LABELS[key],
          count: data["count"].to_i,
          mrr_cents: data["mrr_cents"].to_i,
          arr_cents: data["arr_cents"].to_i
        }
      end.compact
    end

    def funnel
      @funnel ||= begin
        live = live_funnel
        {
          "signups" => live["signups"],
          "prompted" => live["prompted"],
          "wrote" => live["wrote"],
          "wrote_72h" => live["wrote_72h"],
          "upgraded" => live["upgraded"]
        }
      end
    end

    def funnel_rows
      previous = 0
      FUNNEL_LABELS.map.with_index do |(key, label), index|
        count = funnel[key].to_i
        of_signups = percent(count, funnel["signups"])
        of_previous = index.zero? ? nil : percent(count, previous)
        previous = count
        { key: key, label: label, count: count, of_signups: of_signups, of_previous: of_previous }
      end
    end

    def first_entry_activation_rate
      live_first_entry_rate || latest_snapshot&.first_entry_activation_rate
    end

    def three_entry_activation_rate
      live_three_entry_rate || latest_snapshot&.three_entry_activation_rate
    end

    def retention
      {
        pro_7d: live_active_count(7, :pro),
        pro_30d: live_active_count(30, :pro),
        pro_90d: live_active_count(90, :pro),
        pro_365d: live_active_count(365, :pro),
        free_7d: live_active_count(7, :free),
        free_30d: live_active_count(30, :free),
        free_90d: live_active_count(90, :free),
        free_365d: live_active_count(365, :free)
      }
    end

    def paid_inactive_30d
      [pro_user_count - retention[:pro_30d], 0].max
    end

    def paid_inactive_90d
      [pro_user_count - retention[:pro_90d], 0].max
    end

    def loyalty
      @loyalty ||= AdminStats.new.active_users_breakdown(since: 1.year.ago)
    end

    def sources
      @sources ||= begin
        rows = live_source_rows
        rows.sort_by { |row| [-row[:upgrades_30d], -row[:mrr_cents], -row[:signups_30d]] }.first(20)
      end
    end

    def email_health
      @email_health ||= {
        sent: latest_snapshot&.email_sent_count,
        failed: latest_snapshot&.email_failed_count,
        replies: latest_snapshot&.email_replies_count,
        delivery_rate: latest_snapshot&.email_delivery_rate,
        reply_rate: latest_snapshot&.email_reply_rate,
        lifetime_sent: User.not_deleted.sum(:emails_sent),
        lifetime_received: User.not_deleted.sum(:emails_received)
      }
    end

    def cash_collected_month_cents
      amount = Payment.where("date >= ?", as_of.to_date.beginning_of_month).sum(:amount)
      (BigDecimal(amount.to_s) * 100).round
    end

    def cash_collected_year_cents
      amount = Payment.where("date >= ?", as_of.to_date.beginning_of_year).sum(:amount)
      (BigDecimal(amount.to_s) * 100).round
    end

    def cash_collected_all_time_cents
      (BigDecimal(Payment.sum(:amount).to_s) * 100).round
    end

    def payment_count
      Payment.count
    end

    def at_risk
      revenue.at_risk
    end

    def upcoming_renewals_count
      revenue.upcoming_annual_renewals.size
    end

    def inventory
      @inventory ||= begin
        users = User.not_deleted
        pro = users.pro_only
        {
          entries: Entry.unscoped.count,
          photos: Entry.unscoped.only_images.count,
          users: users.count,
          pro: pro.count,
          free: users.free_only.count,
          monthly: pro.monthly.count,
          yearly: pro.yearly.count,
          forever: pro.forever.count,
          stripe: pro.payhere_only.count,
          gumroad: pro.gumroad_only.count,
          paypal: pro.paypal_only.count
        }
      end
    end

    def pro_share_of_users
      percent(pro_user_count, user_count)
    end

    def yearly_share_of_pro
      percent(inventory[:yearly], pro_user_count)
    end

    def lifetime_reply_rate
      percent(email_health[:lifetime_received], email_health[:lifetime_sent])
    end

    def chart_mrr
      snapshot_series { |snap| (snap.mrr_cents / 100.0).round(2) }
    end

    def chart_arr
      snapshot_series { |snap| (snap.arr_cents / 100.0).round(2) }
    end

    def chart_activation
      snapshot_series do |snap|
        next unless snap.first_entry_activation_rate

        (snap.first_entry_activation_rate.to_f * 100).round(1)
      end
    end

    def chart_reply_rate
      snapshot_series do |snap|
        next unless snap.email_reply_rate

        (snap.email_reply_rate.to_f * 100).round(1)
      end
    end

    def chart_signups
      User.not_deleted.where("created_at >= ?", 90.days.ago).group_by_week(:created_at, format: "%b %d").count
    end

    def chart_entries
      Entry.unscoped.where("date >= ?", 90.days.ago).where("date < ?", as_of + 1.day).group_by_week(:date, format: "%b %d").count
    end

    def chart_cash
      Payment.where("date > ?", 1.year.ago).group_by_month(:date, format: "%b %Y").sum(:amount)
    end

    def chart_upgrades
      first_payments = Payment.where("date >= ?", 90.days.ago).group(:user_id).minimum(:date)
      grouped = Hash.new(0)
      first_payments.each_value do |paid_at|
        next if paid_at.blank?

        grouped[paid_at.to_date.beginning_of_week(:sunday).strftime("%b %d")] += 1
      end
      grouped.sort.to_h
    end

    def chart_net_mrr
      [
        { name: "New MRR", data: snapshot_series { |snap| (snap.gross_new_mrr_cents / 100.0).round(2) } },
        { name: "Churned MRR", data: snapshot_series { |snap| (snap.churned_mrr_cents / 100.0).round(2) } }
      ]
    end

    def format_cents(cents)
      ActionController::Base.helpers.number_to_currency((cents.to_i / 100.0), precision: 2)
    end

    def format_rate(rate)
      return "—" if rate.blank?

      "#{(rate.to_f * 100).round(1)}%"
    end

    def format_delta(cents)
      return "—" if cents.nil?

      prefix = cents.positive? ? "+" : ""
      "#{prefix}#{format_cents(cents)}"
    end

    def share_rate(part, whole)
      percent(part, whole)
    end

    def delta_direction(cents)
      return "flat" if cents.nil? || cents.zero?
      cents.positive? ? "up" : "down"
    end

    private

    def snapshot_on_or_before(day)
      BusinessMetricSnapshot.where("captured_on <= ?", day).order(captured_on: :desc).first
    end

    def comparable_snapshots?
      latest_snapshot.present? && week_ago_snapshot.present?
    end

    def rate_fell?(attribute)
      current = latest_snapshot.public_send(attribute)
      previous = week_ago_snapshot.public_send(attribute)
      return false if current.blank? || previous.blank?

      current.to_f < previous.to_f
    end

    def live_funnel
      start_at = as_of - 30.days
      sql = ActiveRecord::Base.sanitize_sql_array([
        <<~SQL.squish,
          SELECT
            COUNT(*)::bigint AS signups,
            COUNT(*) FILTER (WHERE users.emails_sent > 0)::bigint AS prompted,
            COUNT(*) FILTER (WHERE first_entries.first_at IS NOT NULL)::bigint AS wrote,
            COUNT(*) FILTER (
              WHERE first_entries.first_at IS NOT NULL
                AND first_entries.first_at <= users.created_at + INTERVAL '72 hours'
            )::bigint AS wrote_72h,
            COUNT(*) FILTER (WHERE users.plan ILIKE '%pro%')::bigint AS upgraded
          FROM users
          LEFT JOIN LATERAL (
            SELECT MIN(created_at) AS first_at
            FROM entries
            WHERE entries.user_id = users.id
          ) first_entries ON TRUE
          WHERE users.deleted_at IS NULL
            AND users.created_at >= ?
            AND users.created_at <= ?
        SQL
        start_at,
        as_of
      ])
      row = ActiveRecord::Base.connection.select_one(sql) || {}
      {
        "signups" => row["signups"].to_i,
        "prompted" => row["prompted"].to_i,
        "wrote" => row["wrote"].to_i,
        "wrote_72h" => row["wrote_72h"].to_i,
        "upgraded" => row["upgraded"].to_i
      }
    end

    def live_first_entry_rate
      stats = activation_window(
        start_at: as_of - 30.days - 72.hours,
        end_at: as_of - 72.hours,
        filter: "first_entries.first_at IS NOT NULL AND first_entries.first_at <= users.created_at + INTERVAL '72 hours'"
      )
      rate(stats[:activated], stats[:eligible])
    end

    def live_three_entry_rate
      stats = activation_window(
        start_at: as_of - 44.days,
        end_at: as_of - 14.days,
        extra_join: <<~SQL.squish,
          LEFT JOIN LATERAL (
            SELECT COUNT(*) AS n
            FROM entries
            WHERE entries.user_id = users.id
              AND entries.created_at <= users.created_at + INTERVAL '14 days'
          ) entry_counts ON TRUE
        SQL
        filter: "entry_counts.n >= 3"
      )
      rate(stats[:activated], stats[:eligible])
    end

    def activation_window(start_at:, end_at:, filter:, extra_join: "")
      sql = ActiveRecord::Base.sanitize_sql_array([
        <<~SQL.squish,
          SELECT
            COUNT(*)::bigint AS eligible,
            COUNT(*) FILTER (WHERE #{filter})::bigint AS activated
          FROM users
          LEFT JOIN LATERAL (
            SELECT MIN(created_at) AS first_at
            FROM entries
            WHERE entries.user_id = users.id
          ) first_entries ON TRUE
          #{extra_join}
          WHERE users.deleted_at IS NULL
            AND users.created_at >= ?
            AND users.created_at <= ?
        SQL
        start_at,
        end_at
      ])
      row = ActiveRecord::Base.connection.select_one(sql) || {}
      { eligible: row["eligible"].to_i, activated: row["activated"].to_i }
    end

    def live_active_count(days, plan)
      plan_clause = plan == :pro ? "users.plan ILIKE '%pro%'" : "(users.plan ILIKE '%free%' OR users.plan IS NULL)"
      sql = ActiveRecord::Base.sanitize_sql_array([
        <<~SQL.squish,
          SELECT COUNT(*)::bigint
          FROM (
            SELECT DISTINCT user_id
            FROM entries
            WHERE date >= ? AND date <= ?
          ) active_entries
          INNER JOIN users ON users.id = active_entries.user_id
          WHERE users.deleted_at IS NULL
            AND #{plan_clause}
        SQL
        as_of.to_date - days.days,
        as_of
      ])
      ActiveRecord::Base.connection.select_value(sql).to_i
    end

    def live_source_rows
      users_30d = User.not_deleted.where(created_at: (as_of - 30.days)..as_of)
      first_entry_user_ids = Entry.unscoped.where(user_id: users_30d.select(:id)).distinct.pluck(:user_id)
      signups = users_30d.group("COALESCE(NULLIF(referrer, ''), 'direct')").count
      upgrades = users_30d.pro_only.group("COALESCE(NULLIF(referrer, ''), 'direct')").count
      firsts = users_30d.where(id: first_entry_user_ids).group("COALESCE(NULLIF(referrer, ''), 'direct')").count
      mrr_by_source = Hash.new(0)
      revenue.recurring.each do |subscriber|
        source = subscriber.referrer.presence || "direct"
        mrr_by_source[source] += revenue.mrr_cents_for(subscriber)
      end

      (signups.keys + mrr_by_source.keys).uniq.map do |source|
        signups_count = signups[source].to_i
        firsts_count = firsts[source].to_i
        upgrades_count = upgrades[source].to_i
        {
          source: source,
          signups_30d: signups_count,
          first_entries_30d: firsts_count,
          upgrades_30d: upgrades_count,
          mrr_cents: mrr_by_source[source].to_i,
          activation_rate: rate(firsts_count, signups_count),
          conversion_rate: rate(upgrades_count, signups_count)
        }
      end
    end

    def snapshot_series
      BusinessMetricSnapshot.chronological.each_with_object({}) do |snap, memo|
        value = yield(snap)
        memo[snap.captured_on.strftime("%b %-d")] = value unless value.nil?
      end
    end

    def pro_user_count
      inventory[:pro]
    end

    def user_count
      inventory[:users]
    end

    def percent(part, whole)
      return nil if whole.to_i.zero?

      (part.to_f / whole).round(4)
    end

    def rate(part, whole)
      percent(part, whole)
    end
  end
end
