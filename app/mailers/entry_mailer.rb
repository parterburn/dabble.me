class EntryMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)
  add_template_helper(EntriesHelper)

  def send_entry(user, random_inspiration)
    @random_inspiration = random_inspiration
    @user = user
    @user.increment!(:emails_sent)
    @random_entry = user.random_entry(Time.now.in_time_zone(user.send_timezone).strftime('%Y-%m-%d'))
    if @random_entry.present?
      @random_entry_image_url = @random_entry.image_url_cdn
    end

    email = mail  from: "Dabble Me ✏ <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>",
                  to: "#{user.cleaned_to_address}",
                  subject: "It's #{Time.now.in_time_zone(user.send_timezone).strftime('%A, %b %-d')}. How was your day?",
                  html: (render_to_string(template: '../views/entry_mailer/send_entry.html')).to_str,
                  text: (render_to_string(template: '../views/entry_mailer/send_entry.text')).to_str

    email.mailgun_options = { tag: 'Entry' }
  end
end
