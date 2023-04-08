class EntryMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)
  helper EntriesHelper

  def send_entry(user, random_inspiration, send_day: nil, as_ai: false)
    @send_day = send_day.presence || Time.now.in_time_zone(user.send_timezone)
    @random_inspiration = random_inspiration
    @user = user
    @user.increment!(:emails_sent)
    @user.update_columns(last_sent_at: Time.now)
    @random_entry = user.random_entry(@send_day.strftime('%Y-%m-%d'))
    if @random_entry.present?
      @random_entry_image_url = @random_entry.image_url_cdn
    end

    domain = as_ai ? ENV['SMTP_DOMAIN'].gsub('post', 'ai') : ENV['SMTP_DOMAIN']
    from = as_ai ? "Dabble Me AI 🪄" : "Dabble Me ✏"
    email = mail  from: "#{from} <#{user.user_key}@#{domain}>",
                  to: "#{user.cleaned_to_address}",
                  subject: "It's #{@send_day.strftime('%A, %b %-d')}. How was your day?",
                  html: (render_to_string(template: '../views/entry_mailer/send_entry.html')).to_str,
                  text: (render_to_string(template: '../views/entry_mailer/send_entry.text')).to_str

    email.mailgun_options = { tag: 'Entry' }
  end

  def respond_as_ai(user, entry)
    message_id = entry.original_email&.dig("headers", "Message-ID")
    reply_to = entry.original_email&.dig("headers", "In-Reply-To")
    references = entry.original_email&.dig("headers", "References")
    message_ids = [message_id, reply_to, references].flatten.compact
    @user = user

    # do the AI thing
    @ai_answer = process_as_ai(entry)
    entry.body = "#{entry.body}<hr><strong>DabbleMeGPT</strong><br/>#{ActionController::Base.helpers.simple_format(@ai_answer)}"
    entry.save

    email = mail  from: "Dabble Me AI 🪄 ✏ <#{user.user_key}@#{ENV['SMTP_DOMAIN'].gsub('post', 'ai')}>",
                  to: "#{user.cleaned_to_address}",
                  subject: "re: It's #{entry.date.strftime('%A, %b %-d')}. How was your day?",
                  html: (render_to_string(template: '../views/entry_mailer/respond_as_ai.html')).to_str,
                  text: (render_to_string(template: '../views/entry_mailer/respond_as_ai.text')).to_str,
                  headers:  {
                    "In-Reply-To" => message_id,
                    "References"  => message_ids&.join(" ")
                  }

    email.mailgun_options = { tag: 'AI Entry' }
  end

  private

  def process_as_ai(entry)
    client = OpenAI::Client.new

    messages = [{
      role: "system",
      content: %Q(
        You are a trained psycho-therapist.

        Respond to a journal entry for the day as the therapist with a light and witty analysis. If the sentiment of the journal entry is positive, you can be funny in your response: write a haiku, a short song, a knock knock joke, responding as Dr. Seuss etc.

        Only on your first response, ask one follow up question that will help the user dig into their experience or feelings more. Do not ask more than one  question during the entire conversation.

        Once a user has answered your follow up question, on your next response close out the conversation by celebrating the user for taking the time to journal with a positive and inspiring personal growth-focused message. Be more serious, do not respond in haiku/song/joke/etc.
      )
    }]

    entry.text_bodies_for_ai.each do |body|
      role = body.include?("DabbleMeGPT") ? "assistant" : "user"
      messages << {
        role: role,
        content: Nokogiri::HTML.parse(ReverseMarkdown.convert(body, unknown_tags: :bypass)).text
      }
    end

    response = client.chat(
      parameters: {
          model: "gpt-3.5-turbo",
          messages: messages,
        temperature: 0.7,
      })
    response.dig("choices", 0, "message", "content")
  end
end
