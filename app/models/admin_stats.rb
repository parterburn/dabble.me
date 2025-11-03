class AdminStats
  def users_by_week_since(date)
    users_created_since(date).group_by_week(:created_at, format: "%b %d").count
  end

  def pro_users_by_week_since(date)
    upgrade_dates = []
    User.pro_only.each do |user|
      first_payment = user.payments.order('payments.date').try(:first).try(:date)
      if first_payment.present? && first_payment > date
        upgrade_dates << first_payment.beginning_of_week(:sunday).strftime('%Y-%m-%d')
      end
    end
    Hash[upgrade_dates.group_by_week{ |u| u }.map { |k, v| [k.strftime('%b %d'), v.size] }]
  end

  def entries_by_week_since(date)
    Entry.unscoped.where("date >= ?", date).where("date < ?", (Time.now + 1.day)).group_by_week(:date, format: "%b %d").count
  end

  def emails_sent_by_month_since(date)
    if ENV['MAILGUN_API_KEY'].present?
      uri = URI("https://api.mailgun.net/v3/dabble.me/stats/total?event[]=accepted&event[]=failed&event[]=opened&resolution=month&start=#{date.to_i}")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth 'api', "#{ENV['MAILGUN_API_KEY']}"

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) {|http|
        http.request(req)
      }
      stats = JSON.parse(res.body)
      requests_hash = Hash.new
      unique_opens_hash = Hash.new
      failed_hash = Hash.new
      stats['stats'].each do |stat|
        formatted_date = Date.parse(stat['time']).strftime('%b %Y')
        requests_hash[formatted_date] = stat['accepted']['total']
        failed_hash[formatted_date] = stat['failed']['total']
        unique_opens_hash[formatted_date] = stat['opened']['total']
      end
      received_emails_hash = received_emails(date)
      [
        { name: "requests sent", data: requests_hash },
        { name: "failed sent", data: failed_hash },
        { name: "unique_opens", data: unique_opens_hash },
        { name: "received", data: received_emails_hash }
      ]
    end
  end

  def received_emails(date)
    if ENV['MAILGUN_API_KEY'].present?
      uri = URI("https://api.mailgun.net/v3/#{ENV['SMTP_DOMAIN']}/stats/total?event=delivered&resolution=month&start=#{date.to_i}")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth 'api', "#{ENV['MAILGUN_API_KEY']}"

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) {|http|
        http.request(req)
      }
      stats = JSON.parse(res.body)
      received_hash = Hash.new
      stats['stats'].each do |stat|
        formatted_date = Date.parse(stat['time']).strftime('%b %Y')
        received_hash[formatted_date] = stat['delivered']['total']
      end
      received_hash
    end
  end

  def payments_by_month(date)
    Payment.where('date > ?', date).group_by_month(:date, format: "%b").sum(:amount)
  end

  def users_created_since(date)
    User.where("created_at >= ?", date)
  end

  # def free_users_created_since(date)
  #   User.free_only.where("created_at >= ?", date)
  # end

  def upgraded_users_since(date)
    pro_users = []
    User.pro_only.includes(:payments).order("payments.created_at ASC").each do | user|
      first_payment = user.payments.order('payments.date').try(:first).try(:date)
      if first_payment.present? && first_payment > date
        pro_users << user
      end
    end
    pro_users
  end

  # def bounced_users_since(date)
  #   User.where("emails_bounced > 0").where("updated_at >= ?", date)
  # end

  def entries_per_day_for(user)
    (entry_count_for(user) / account_age_for(user).to_f).to_f.round(1)
  rescue ZeroDivisionError
    0
  end

  def paid_status_for(user)
    entries_per_day = entries_per_day_for(user)

    if entry_count_for(user) == 0
      "danger"
    elsif entries_per_day <= 0.2
      "warning"
    else
      "great"
    end
  end

  # Active users breakdown over a period (defaults to last year)
  # Returns a hash with keys :all, :pro, :free, each containing counts and user lists:
  # {
  #   yearly_count:, monthly_count:, weekly_count:, daily_count:,
  #   weekly_users: [User], daily_users: [User]
  # }
  def active_users_breakdown(since: 1.year.ago)
    {
      all: active_counts_for_scope(User.all, since: since),
      pro: active_counts_for_scope(User.pro_only, since: since),
      free: active_counts_for_scope(User.free_only, since: since)
    }
  end

  private

  def entry_count_for(user)
    user.entries.where("created_at >= ?", 30.days.ago).count
  end

  def account_age_for(user)
    [30, Time.zone.now.to_date - user.created_at.to_date].min
  end

  def active_counts_for_scope(user_scope, since:)
    period_end = Time.zone.now.end_of_day
    # Remove default_scope ORDER to avoid DISTINCT/ORDER BY error
    entries_in_period = Entry.unscoped.where(date: since..period_end)

    # Thresholds relative to a one-year window
    months_required = 12
    weeks_required = 52
    days_required = 365

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

    scoped_yearly_ids = user_scope.where(id: yearly_ids).pluck(:id)
    scoped_monthly_ids = user_scope.where(id: monthly_ids).pluck(:id)
    scoped_weekly_ids = user_scope.where(id: weekly_ids).pluck(:id)
    scoped_daily_ids = user_scope.where(id: daily_ids).pluck(:id)

    {
      yearly_count: scoped_yearly_ids.size,
      monthly_count: scoped_monthly_ids.size,
      weekly_count: scoped_weekly_ids.size,
      daily_count: scoped_daily_ids.size,
      weekly_users: User.where(id: scoped_weekly_ids).order(:first_name, :last_name),
      daily_users: User.where(id: scoped_daily_ids).order(:first_name, :last_name)
    }
  end
end
