class EntryMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)

  def send_entry(user)
    @user = user
    @random_entry = user.random_entry
    @random_inspiration = random_inspiration

    headers['x-smtpapi'] = { :category => [ "Entry" ] }.to_json
    mail from: "Dabble Me <post+#{user.user_key}@dabble.me>",
         to: "#{user.full_name} <#{user.email}>",
         subject: "It's #{Time.now.in_time_zone(user.send_timezone).strftime("%A, %B %-d")} - How did your day go?"

    user.increment!(:emails_sent)

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