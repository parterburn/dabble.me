class EntryMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)
  helper EntriesHelper

  def send_entry(user, random_inspiration, send_day: nil)
    @send_day = send_day.presence || Time.now.in_time_zone(user.send_timezone)
    @random_inspiration = random_inspiration
    @user = user
    @user.increment!(:emails_sent)
    @user.update_columns(last_sent_at: Time.now)
    @random_entry = user.random_entry(@send_day.strftime('%Y-%m-%d'))
    if @random_entry.present?
      @random_entry_image_url = @random_entry.image_url_cdn
    end

    email = mail  from: "Dabble Me ✏ <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>",
                  to: "#{user.cleaned_to_address}",
                  subject: "It's #{@send_day.strftime('%A, %b %-d')}. How was your day?",
                  html: (render_to_string(template: '../views/entry_mailer/send_entry.html')).to_str,
                  text: (render_to_string(template: '../views/entry_mailer/send_entry.text')).to_str

    email.mailgun_options = { tag: 'Entry' }
  end

  def respond_as_ai(user, entry)
    @user = user

    # do the AI thing
    @ai_answer = entry.ai_response
    return unless @ai_answer.present?

    entry.body = "#{entry.body}<hr><div data-content='dabblemegpt'><strong>🤖 DabbleMeGPT:</strong><br/>#{ActionController::Base.helpers.simple_format(@ai_answer.gsub(/<hr\/?>/, "").gsub(/\A\n*/, ""), {}, sanitize: false)}</div>"
    entry.save
    @entry = entry

    set_reply_headers(entry)
    email = mail  from: "DabbleMeGPT 🪄 <#{user.user_key}@#{ENV['SMTP_DOMAIN'].gsub('post', 'ai')}>",
                  to: "#{user.cleaned_to_address}",
                  subject: "Re: #{subject(entry)}",
                  html: (render_to_string(template: '../views/entry_mailer/respond_as_ai.html')).to_str,
                  text: (render_to_string(template: '../views/entry_mailer/respond_as_ai.text')).to_str

    email.mailgun_options = { tag: 'AI Entry' }
  end

  def send_entry_image_error(user, entry)
    set_reply_headers(entry)
    email = mail  from: "Dabble Me ✏ <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>",
                  to: "hello@#{ENV['MAIN_DOMAIN']}",
                  subject: "Re: #{subject(entry)}",
                  content_type: "text/html",
                  body: "The image for your entry on <a href='#{::Rails.application.routes.url_helpers.entry_url(entry)}'>#{entry.date.strftime('%B %d, %Y')}</a> could not be saved. Try converting it to a lower resolution JPEG image and use the <a href='#{::Rails.application.routes.url_helpers.edit_entry_url(entry)}'>web interface</a> to re-upload it.\n\n##{entry.errors.full_messages.join(', ')}"
    email.mailgun_options = { tag: "Entry Image Error" }
  end

  private

  def subject(entry)
    if entry.date.after?(6.months.ago)
      subject ||= entry.original_email&.dig("headers", "Subject").presence || "Entry for #{entry.date.strftime('%A, %b %-d, %Y')}"
    else
      subject = "Entry for #{entry.date.strftime('%A, %b %-d, %Y')}"
    end
  end

  def set_reply_headers(entry)
    return unless entry.present? && entry.original_email.present?

    # Header must first be nullified before being reset
    message_id = entry.original_email&.dig("headers", "Message-ID")
    reply_to = entry.original_email&.dig("headers", "In-Reply-To")
    references = entry.original_email&.dig("headers", "References")
    message_ids = [message_id, reply_to, references].flatten.compact
    headers['In-Reply-To'] = nil
    headers['References'] = nil
    headers['In-Reply-To'] = message_id
    headers['References'] = message_ids&.join(" ")
  end
end
