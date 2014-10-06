class AdminDashboard
  def users_by_day_since(date)
    User.where("created_at >= ?", date).group_by_day(:created_at).count
  end

  def entries_by_day_since(date)
    Entry.where("date >= ?", date).group_by_day(:date).count
  end

  def users_created_since(date)
    User.where("created_at >= ?", date)
  end

  def entries_per_day_for(user)
    (entry_count_for(user) / account_age_for(user)).to_f.round(2)
  rescue ZeroDivisionError
    0
  end

  private

  def entry_count_for(user)
    user.entries.where("created_at >= ?", user.created_at.to_date).count
  end

  def account_age_for(user)
    Date.today - user.created_at.to_date
  end
end