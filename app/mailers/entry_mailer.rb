class EntryMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)
  include FilepickerRails::ApplicationHelper

  def send_entry(user)
    @user = user
    @random_entry = user.random_entry(Time.now.in_time_zone(user.send_timezone).strftime('%Y-%m-%d'))
    @random_entry_filepicker_url = filepicker_image_url(@random_entry.image_url, w: 300, h: 300, fit: 'max', cache: true, rotate: :exif) if @random_entry.present? && @random_entry.image_url.present?
    @random_inspiration = random_inspiration

    headers['X-Mailgun-Tag'] = 'Entry'
    mail from: "Dabble Me <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>",
         to: "#{user.full_name} <#{user.email}>",
         subject: "It's #{Time.now.in_time_zone(user.send_timezone).strftime('%A, %b %-d')} - How did your day go?"

    user.increment!(:emails_sent)
  end

  private

  def random_inspiration
    return nil unless (count = Inspiration.without_ohlife_or_email.count) > 0
    Inspiration.without_ohlife_or_email.offset(rand(count)).first
  end
end
