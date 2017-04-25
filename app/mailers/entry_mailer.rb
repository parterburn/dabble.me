class EntryMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)

  def send_entry(user)
    @user = user
    @user.increment!(:emails_sent)
    #@random_entry = user.random_entry(Time.now.in_time_zone(user.send_timezone).strftime('%Y-%m-%d'))
    @random_entry = user.entries.find(17)
    if @random_entry.present?
      @random_entry_image_url = @random_entry.image_url_cdn
    end
    @random_inspiration = random_inspiration

    email = mail  from: "Dabble Me ✏ <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>",
                  to: "#{user.cleaned_to_address}",
                  subject: "It's #{Time.now.in_time_zone(user.send_timezone).strftime('%A, %b %-d')}. How was your day?"

    email.mailgun_options = { tag: 'Entry' }
  end

  private

  def random_inspiration
    return nil unless (count = Inspiration.without_imports_or_email.count) > 0
    Inspiration.without_imports_or_email.offset(rand(count)).first
  end
end
