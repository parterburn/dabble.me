class AdminStats
  def users_by_week_since(date)
    users_created_since(date).group_by_week(:created_at, format: "%b %d").count
  end

  def pro_users_by_week_since(date)
    upgrade_dates = []
    User.pro_only.includes(:payments).each do |user|
      if user.payments.present? && user.payments.first.date > date
        upgrade_dates << user.payments.order('payments.date').first.date.beginning_of_week(:sunday).strftime('%Y-%m-%d')
      end
    end
    Hash[upgrade_dates.group_by_week{ |u| u }.map { |k, v| [k.strftime('%b %d'), v.size] }]
  end

  def entries_by_week_since(date)
    Entry.unscoped.where("date >= ?", date).where("date < ?", (Time.now + 1.day)).group_by_week(:date, format: "%b %d").count
  end

  def emails_sent_by_month_since(date)
    if ENV['SENDGRID_API_KEY'].present?
      uri = URI("https://api.sendgrid.com/v3/stats?aggregated_by=month&start_date=#{date.strftime('%Y-%m-%d')}&end_date=#{(Time.now - 1.day).strftime('%Y-%m-%d')}")
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{ENV['SENDGRID_API_KEY']}"

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) {|http|
        http.request(req)
      }
      stats = JSON.parse(res.body)
      requests_hash = Hash.new
      unique_opens_hash = Hash.new
      failed_hash = Hash.new
      stats.each do |stat|
        formatted_date = Date.parse(stat['date']).strftime('%b %Y')
        requests_hash[formatted_date] = stat['stats'].first['metrics']['requests']
        failed_hash[formatted_date] = stat['stats'].first['metrics']['requests'] - stat['stats'].first['metrics']['delivered']
        unique_opens_hash[formatted_date] = stat['stats'].first['metrics']['unique_opens']
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
    if ENV['SENDGRID_API_KEY'].present?
      uri = URI("https://api.sendgrid.com/v3/user/webhooks/parse/stats?aggregated_by=month&start_date=#{date.strftime('%Y-%m-%d')}&end_date=#{(Time.now - 1.day).strftime('%Y-%m-%d')}")
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{ENV['SENDGRID_API_KEY']}"

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) {|http|
        http.request(req)
      }
      stats = JSON.parse(res.body)
      received_hash = Hash.new
      stats.each do |stat|
        formatted_date = Date.parse(stat['date']).strftime('%b %Y')
        received_hash[formatted_date] = stat['stats'].first['metrics']['received']
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

  def upgraded_users_since(date)
    pro_users = []
    User.pro_only.includes(:payments).each do |user|
      if user.payments.present? && user.payments.order('payments.date').first.date > date
        pro_users << user
      end
    end
    pro_users
  end

  def entries_per_day_for(user)
    (entry_count_for(user) / account_age_for(user)).to_f.round(1)
  rescue ZeroDivisionError
    0
  end

  def paid_status_for(user)
    entries_per_day = entries_per_day_for(user)

    if entries_per_day <= 0.02
      "danger"
    elsif entries_per_day <= 0.2
      "warning"
    else
      "great"
    end
  end

  private

  def entry_count_for(user)
    user.entries.where("created_at >= ?", user.created_at.to_date).count
  end

  def account_age_for(user)
    [30, Time.zone.now.to_date - user.created_at.to_date].min
  end
end