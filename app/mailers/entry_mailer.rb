class EntryMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)

  def send_entry(user)
    @user = user
    @random_entry = user.random_entry(Time.now.strftime("%Y-%m-%d"))
    @random_inspiration = random_inspiration

    headers['x-smtpapi'] = { :category => [ "Entry" ] }.to_json
    mail from: "Dabble Me <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>",
         to: "#{user.full_name} <#{user.email}>",
         subject: "It's #{Time.now.in_time_zone(user.send_timezone).strftime("%A, %b %-d")} - How did your day go?"

    user.increment!(:emails_sent)
  end

  def import_finished(user, messages)
    @messages = messages
    mail from: "Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>",
         to: "#{user.full_name} <#{user.email}>",
         subject: "OhLife Photo Import Complete"
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