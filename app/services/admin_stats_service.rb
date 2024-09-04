class AdminStatsService
  def generate_stats
    {
      all_count: Entry.count,
      photos_count: Entry.with_photos.count,
      ai_entries_count: Entry.ai_generated.count,
      ai_users_count: User.with_ai_entries.count,
      total_users: User.count,
      pro_users: User.pro.count,
      users: {
        monthly: User.pro.monthly.count,
        yearly: User.pro.yearly.count,
        forever: User.pro.forever.count,
        payhere_only: User.pro.payhere_only.count,
        gumroad_only: User.pro.gumroad_only.count,
        paypal_only: User.pro.paypal_only.count
      },
      referral_users: User.with_referrals.group(:referrer).count,
      emails_sent_total: User.sum(:emails_sent),
      emails_received_total: User.sum(:emails_received),
      users_by_week: User.group_by_week(:created_at, last: 90.days).count,
      pro_users_by_week: User.pro.group_by_week(:created_at, last: 90.days).count,
      entries_by_week: Entry.group_by_week(:created_at, last: 90.days).count,
      emails_sent_by_month: User.group_by_month(:created_at, last: 90.days).sum(:emails_sent),
      payments_by_month: Payment.group_by_month(:created_at, last: 1.year).sum(:amount)
    }
  end
end
