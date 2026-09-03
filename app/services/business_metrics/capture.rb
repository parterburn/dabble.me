# frozen_string_literal: true

module BusinessMetrics
  class Capture
    class << self
      def call(on: Date.current)
        new(date: on).call
      end
    end

    def initialize(date:)
      @date = date.to_date
      @as_of = Time.use_zone("UTC") { date.end_of_day }
    end

    def call
      snapshot = BusinessMetricSnapshot.find_or_initialize_by(captured_on: date)
      snapshot.assign_attributes(attributes)
      snapshot.save!
      snapshot
    end

    private

    attr_reader :date, :as_of

    def attributes
      revenue = RevenueMetrics.current(as_of: as_of)
      previous = previous_snapshot
      deltas = subscriber_deltas(revenue, previous)
      activation = activation_metrics
      activity = activity_metrics
      email = email_metrics
      cash_cents = cash_collected_cents
      mcp_usage = Mcp::Usage.new(as_of: [as_of, Time.current].min)
      mcp = mcp_usage.summary

      {
        mrr_cents: revenue.mrr_cents,
        arr_cents: revenue.arr_cents,
        gross_new_mrr_cents: deltas[:gross_new_mrr_cents],
        churned_mrr_cents: deltas[:churned_mrr_cents],
        cash_collected_cents: cash_cents,
        recurring_subscriber_count: revenue.recurring_subscriber_count,
        new_subscriber_count: deltas[:new_subscriber_count],
        canceled_subscriber_count: deltas[:canceled_subscriber_count],
        lifetime_subscriber_count: revenue.lifetime_subscriber_count,
        active_pro_7d: activity[:active_pro_7d],
        active_pro_30d: activity[:active_pro_30d],
        active_pro_90d: activity[:active_pro_90d],
        active_pro_365d: activity[:active_pro_365d],
        active_free_7d: activity[:active_free_7d],
        active_free_30d: activity[:active_free_30d],
        active_free_90d: activity[:active_free_90d],
        active_free_365d: activity[:active_free_365d],
        paid_inactive_30d: activity[:paid_inactive_30d],
        paid_inactive_90d: activity[:paid_inactive_90d],
        signups_30d: activation[:signups_30d],
        first_entry_72h_30d: activation[:first_entry_72h_30d],
        three_entry_14d_30d: activation[:three_entry_14d_30d],
        first_entry_activation_rate: activation[:first_entry_activation_rate],
        three_entry_activation_rate: activation[:three_entry_activation_rate],
        email_sent_count: email[:sent],
        email_failed_count: email[:failed],
        email_replies_count: email[:replies],
        email_delivery_rate: email[:delivery_rate],
        email_reply_rate: email[:reply_rate],
        plan_breakdown: revenue.plan_breakdown,
        acquisition_breakdown: acquisition_breakdown(revenue),
        subscriber_map: revenue.subscriber_map,
        mcp_connected_users: mcp[:connected_now],
        mcp_active_users_7d: mcp[:active_users_7d],
        mcp_active_users_30d: mcp[:active_users_30d],
        mcp_tool_calls: mcp_usage.calls_on(date),
        mcp_tool_breakdown: mcp_usage.tool_breakdown_on(date)
      }
    end

    def previous_snapshot
      BusinessMetricSnapshot.where("captured_on < ?", date).order(captured_on: :desc).first
    end

    def subscriber_deltas(revenue, previous)
      today = revenue.subscriber_map
      yesterday = previous&.subscriber_map || {}
      new_ids = today.keys - yesterday.keys
      canceled_ids = yesterday.keys - today.keys

      {
        new_subscriber_count: new_ids.size,
        canceled_subscriber_count: canceled_ids.size,
        gross_new_mrr_cents: new_ids.sum { |id| today.dig(id, "m").to_i },
        churned_mrr_cents: canceled_ids.sum { |id| yesterday.dig(id, "m").to_i }
      }
    end

    def cash_collected_cents
      amount = Payment.where(date: date.all_day).sum(:amount)
      (BigDecimal(amount.to_s) * 100).round
    end

    def activation_metrics
      funnel = signup_funnel
      first = first_entry_window
      three = three_entry_window

      {
        signups_30d: funnel["signups"],
        first_entry_72h_30d: first[:activated],
        three_entry_14d_30d: three[:activated],
        first_entry_activation_rate: rate(first[:activated], first[:eligible]),
        three_entry_activation_rate: rate(three[:activated], three[:eligible]),
        funnel: funnel
      }
    end

    def signup_funnel
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

    def first_entry_window
      window_counts(
        start_at: as_of - 30.days - 72.hours,
        end_at: as_of - 72.hours,
        filter: "first_entries.first_at IS NOT NULL AND first_entries.first_at <= users.created_at + INTERVAL '72 hours'"
      )
    end

    def three_entry_window
      window_counts(
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
        filter: "entry_counts.n >= 3",
        first_entry_join: true
      )
    end

    def window_counts(start_at:, end_at:, filter:, extra_join: "", first_entry_join: true)
      first_join = if first_entry_join
        <<~SQL.squish
          LEFT JOIN LATERAL (
            SELECT MIN(created_at) AS first_at
            FROM entries
            WHERE entries.user_id = users.id
          ) first_entries ON TRUE
        SQL
      else
        ""
      end

      sql = ActiveRecord::Base.sanitize_sql_array([
        <<~SQL.squish,
          SELECT
            COUNT(*)::bigint AS eligible,
            COUNT(*) FILTER (WHERE #{filter})::bigint AS activated
          FROM users
          #{first_join}
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

    def activity_metrics
      as_of_date = date
      windows = {
        active_pro_7d: [7, :pro],
        active_pro_30d: [30, :pro],
        active_pro_90d: [90, :pro],
        active_pro_365d: [365, :pro],
        active_free_7d: [7, :free],
        active_free_30d: [30, :free],
        active_free_90d: [90, :free],
        active_free_365d: [365, :free]
      }

      counts = windows.transform_values do |days, plan|
        active_user_count(since: as_of_date - days.days, plan: plan)
      end

      pro_count = User.not_deleted.pro_only.count
      counts.merge(
        paid_inactive_30d: [pro_count - counts[:active_pro_30d], 0].max,
        paid_inactive_90d: [pro_count - counts[:active_pro_90d], 0].max
      )
    end

    def active_user_count(since:, plan:)
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
        since.beginning_of_day,
        as_of
      ])
      ActiveRecord::Base.connection.select_value(sql).to_i
    end

    def email_metrics
      mailgun = BusinessMetrics::MailgunStats.fetch(date: date)
      replies = Entry.unscoped
                     .where.not(original_email_body: [nil, ""])
                     .where(created_at: date.all_day)
                     .count
      sent = mailgun.sent
      {
        sent: sent,
        failed: mailgun.failed,
        replies: replies,
        delivery_rate: mailgun.delivery_rate,
        reply_rate: sent.positive? ? (replies.to_f / sent) : nil
      }
    end

    def acquisition_breakdown(revenue)
      users_30d = User.not_deleted.where(created_at: (as_of - 30.days)..as_of)
      first_entry_user_ids = Entry.unscoped.where(user_id: users_30d.select(:id)).distinct.pluck(:user_id)
      signups_by_source = users_30d.group("COALESCE(NULLIF(referrer, ''), 'direct')").count
      upgrades_by_source = users_30d.pro_only.group("COALESCE(NULLIF(referrer, ''), 'direct')").count
      first_entries_by_source = users_30d.where(id: first_entry_user_ids).group("COALESCE(NULLIF(referrer, ''), 'direct')").count

      mrr_by_source = Hash.new(0)
      revenue.recurring.each do |subscriber|
        source = subscriber.referrer.presence || "direct"
        mrr_by_source[source] += revenue.mrr_cents_for(subscriber)
      end

      sources = (signups_by_source.keys + mrr_by_source.keys).uniq
      sources.each_with_object({}) do |source, memo|
        memo[source] = {
          "signups_30d" => signups_by_source[source].to_i,
          "first_entries_30d" => first_entries_by_source[source].to_i,
          "upgrades_30d" => upgrades_by_source[source].to_i,
          "mrr_cents" => mrr_by_source[source].to_i
        }
      end
    end

    def rate(part, whole)
      return nil if whole.to_i.zero?

      (part.to_f / whole).round(4)
    end
  end
end
