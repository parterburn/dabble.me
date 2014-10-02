class EntryMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)

  def send_entry(user)
    @user = user
    @random_entry = user.random_entry
    @random_inspiration = random_inspiration


    #TODO: MOVE THIS LOGIC INTO ACTION
    if Time.now.in_time_zone(user.send_timezone).hour == user.send_time.hour
      @should_send_time = true
    else
      @should_send_time = false
    end

    if user.frequency.include? Time.now.in_time_zone(user.send_timezone).strftime('%a')
      @should_send_date = true
    else
      @should_send_date = false
    end

    headers['x-smtpapi'] = { :category => [ "Entry" ] }.to_json
    mail from: "Dabble Me <post+#{user.user_key}@dabble.me>",
         to: "#{user.full_name} <#{user.email}>",
         subject: "It's #{Time.now.in_time_zone(user.send_timezone).strftime("%A, %B %-d")} - How did your day go?"
  end

  private
    def random_inspiration
      if (count = Inspiration.without_ohlife_or_email.count) > 0
        Inspiration.without_ohlife_or_email.offset(rand(count)).first
      else
        nil
      end
    end

end