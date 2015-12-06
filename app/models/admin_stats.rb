class AdminStats
  def users_by_day_since(date)
    [
      { name: 'All Users', data: users_created_since(date).group_by_week(:created_at).count },
      { name: 'Pro Users', data: users_created_since(date).pro_only.group_by_week(:created_at).count }
    ]
  end

  def entries_by_day_since(date)
    Entry.unscoped.where("date >= ?", date).where("date < ?", Time.now).group_by_week(:date).count
  end

  def emails_sent_by_month_since(date)
    uri = URI("https://api.sendgrid.com/v3/stats?aggregated_by=month&start_date=#{date.strftime('%Y-%m-%d')}&end_date=#{Time.now.strftime('%Y-%m-%d')}")
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
      requests_hash[stat['date']] = stat['stats'].first['metrics']['requests']
      failed_hash[stat['date']] = stat['stats'].first['metrics']['requests'] - stat['stats'].first['metrics']['delivered']
      unique_opens_hash[stat['date']] = stat['stats'].first['metrics']['unique_opens']
    end
    [ 
      { name: "requests sent", data: requests_hash },
      { name: "failed sent", data: failed_hash },
      { name: "unique_opens", data: unique_opens_hash },
      { name: "received", data: received_emails(date) }
    ]
  end

  def received_emails(date)
    uri = URI("https://api.sendgrid.com/v3/user/webhooks/parse/stats?aggregated_by=month&start_date=#{date.strftime('%Y-%m-%d')}&end_date=#{Time.now.strftime('%Y-%m-%d')}")
    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{ENV['SENDGRID_API_KEY']}"

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) {|http|
      http.request(req)
    }
    stats = JSON.parse(res.body)
    received_hash = Hash.new
    stats.each do |stat|
      received_hash[stat['date']] = stat['stats'].first['metrics']['received']
    end
    received_hash
  end  

  def payments_by_day_since(date)
    Payment.where("date >= ?", date).group_by_month(:date).sum(:amount)
  end

  def users_created_since(date)
    User.where("created_at >= ?", date)
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
    Time.zone.now.to_date - user.created_at.to_date
  end
end