class AdminStats
  # Loyalty milestones over a period (defaults to last year). These require
  # writing in almost every month/week/day and are not WAU/MAU.
  def active_users_breakdown(since: 1.year.ago)
    {
      all: active_counts_for_scope(User.not_deleted, since: since),
      pro: active_counts_for_scope(User.not_deleted.pro_only, since: since),
      free: active_counts_for_scope(User.not_deleted.free_only, since: since)
    }
  end

  private

  def active_counts_for_scope(user_scope, since:)
    period_end = Time.zone.now.end_of_day
    entries_in_period = Entry.unscoped.where(date: since..period_end)

    months_required = 11
    weeks_required = 51
    days_required = 364

    yearly_ids = entries_in_period.select(:user_id).distinct.pluck(:user_id)

    monthly_ids = entries_in_period
      .group(:user_id)
      .having("COUNT(DISTINCT DATE_TRUNC('month', date)) >= ?", months_required)
      .pluck(:user_id)

    weekly_ids = entries_in_period
      .group(:user_id)
      .having("COUNT(DISTINCT DATE_TRUNC('week', date)) >= ?", weeks_required)
      .pluck(:user_id)

    daily_ids = entries_in_period
      .group(:user_id)
      .having("COUNT(DISTINCT DATE(date)) >= ?", days_required)
      .pluck(:user_id)

    {
      yearly_count: user_scope.where(id: yearly_ids).count,
      monthly_count: user_scope.where(id: monthly_ids).count,
      weekly_count: user_scope.where(id: weekly_ids).count,
      daily_count: user_scope.where(id: daily_ids).count
    }
  end
end
