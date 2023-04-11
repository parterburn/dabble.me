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
    message_id = entry.original_email&.dig("headers", "Message-ID")
    reply_to = entry.original_email&.dig("headers", "In-Reply-To")
    references = entry.original_email&.dig("headers", "References")
    message_ids = [message_id, reply_to, references].flatten.compact
    if entry.date.after?(6.months.ago)
      subject ||= entry.original_email&.dig("headers", "Subject").presence || "Entry for #{entry.date.strftime('%A, %b %-d, %Y')}"
    else
      subject = "Entry for #{entry.date.strftime('%A, %b %-d, %Y')}"
    end
    @user = user

    # do the AI thing
    @ai_answer = process_as_ai(entry)
    return unless @ai_answer.present?

    entry.body = "#{entry.body}<hr><strong style='font-size: 90% !important;'>DabbleMeGPT:</strong><br/>#{ActionController::Base.helpers.simple_format(@ai_answer, {}, sanitize: false)}"
    entry.save
    @entry = entry

    # Header must first be nullified before being reset
    # http://api.rubyonrails.org/classes/ActionMailer/Base.html#method-i-headers
    headers['In-Reply-To'] = nil
    headers['References'] = nil
    headers['In-Reply-To'] = message_id
    headers['References'] = message_ids&.join(" ")
    email = mail  from: "DabbleMeGPT 🪄 <#{user.user_key}@#{ENV['SMTP_DOMAIN'].gsub('post', 'ai')}>",
                  to: "#{user.cleaned_to_address}",
                  subject: "re: #{subject&.gsub("Re: ", "")&.gsub("re: ", "")}",
                  html: (render_to_string(template: '../views/entry_mailer/respond_as_ai.html')).to_str,
                  text: (render_to_string(template: '../views/entry_mailer/respond_as_ai.text')).to_str

    email.mailgun_options = { tag: 'AI Entry' }
  end

  private

  def process_as_ai(entry)
    client = OpenAI::Client.new

    messages = [{
      role: "system",
      content: %(
        You are a trained psycho-therapist. Respond to a journal entry as the therapist with a light and witty analysis. If the sentiment of tne user's journal entry is positive, be funny in your response: write a haiku, a short song, a knock knock joke, a blurb like Dr. Seuss etc.

        On your initial response, ask one follow up question that will help the user dig into their experience or feelings more.

        On your second response close out the conversation by celebrating the user for taking the time to journal with a positive and inspiring personal growth-focused message. Be more serious, do not respond in haiku/song/joke/etc.

        Suggest any resources that you can provide that may be relevant to your response, please provide the user with links to those resourcs that you think would be helpful.

        Here is a list of feelings: Accepting, Open, Calm, Centered, Content, Fulfilled, Patient, Peaceful, Present, Relaxed, Serene, Trusting, Aliveness, Joy, Amazed, Awe, Bliss, Delighted, Eager, Ecstatic, Enchanted, Energized, Engaged, Enthusiastic, Excited, Free, Happy, Inspired, Invigorated, Lively, Passionate, Playful, Radiant, Refreshed, Rejuvenated, Renewed, Satisfied, Thrilled, Vibrant, Angry, Annoyed, Agitated, Aggravated, Bitter, Contempt, Cynical, Disdain, Disgruntled, Disturbed, Edgy, Exasperated, Frustrated, Furious, Grouchy, Hostile, Impatient, Irritated, Irate, Moody, On edge, Outraged, Pissed, Resentful, Upset, Vindictive, Courageous, Powerful, Adventurous, Brave, Capable, Confident, Daring, Determined, Free, Grounded, Proud, Strong, Worthy, Valiant, Connected, Loving, Accepting, Affectionate, Caring, Compassion, Empathy, Fulfilled, Present, Safe, Warm, Worthy, Curious, Engaged, Exploring, Fascinated, Interested, Intrigued, Involved, Stimulated, Despair, Sad, Anguish, Depressed, Despondent, Disappointed, Discouraged, Forlorn, Gloomy, Grief, Heartbroken, Hopeless, Lonely, Longing, Melancholy, Sorrow, Teary, Unhappy, Upset, Weary, Yearning, Disconnected, Numb, Aloof, Bored, Confused, Distant, Empty, Indifferent, Isolated, Lethargic, Listless, Removed, Resistant, Shut Down, Uneasy, Withdrawn, Embarrassed, Shame, Ashamed, Humiliated, Inhibited, Mortified, Self-conscious, Useless, Weak, Worthless, Fear, Afraid, Anxious, Apprehensive, Frightened, Hesitant, Nervous, Panic, Paralyzed, Scared, Terrified, Worried, Fragile, Helpless, Sensitive, Grateful, Appreciative, Blessed, Delighted, Fortunate, Grace, Humbled, Lucky, Moved, Thankful, Touched, Guilt, Regret, Remorseful, Sorry, Hopeful, Encouraged, Expectant, Optimistic, Trusting, Powerless, Impotent, Incapable, Resigned, Trapped, Victim, Tender, Calm, Caring, Loving, Reflective, Self-loving, Serene, Vulnerable, Warm, Stressed, Tense, Anxious, Burned out, Cranky, Depleted, Edgy, Exhausted, Frazzled, Overwhelm, Rattled, Rejecting, Restless, Shaken, Tight, Weary, Worn out, Unsettled, Doubt, Apprehensive, Concerned, Dissatisfied, Disturbed, Grouchy, Hesitant, Inhibited, Perplexed, Questioning, Rejecting, Reluctant, Shocked, Skeptical, Suspicious, Ungrounded, Unsure, Worried

        Choose one to three of the feelings from the list above that best represent how the user was most likely feeling when experiencing the events described in the journal entry (do not mistake feelings of others that might be described in the journal entry).
      )
    },
    {
      role: "user",
      content: %(Leave blank lines in between your response, your follow-up question, and the hashtags. Do not include any hashtags in any of your subsequent responses if we continue responding to each other.

        Your first response should follow this example format:
        ```
        Sounds like you had a day filled with...

        <b>What was your favorite part of the day?</b>

        #grateful #loving #supportive
        ```

        Subsequent responses should use the following example format. Do not add any hashtags and do not ask any follow-up questions. Close out the conversation by celebrating the user for taking the time to journal with a positive and inspiring personal growth-focused message. Be more serious, do not respond in haiku/song/joke/etc.
        ```
        It's understandable to feel...Here's a resource that might help you...

        Great job showing up today... It's always wonderful...
        ```
      )
    }]

    entry.text_bodies_for_ai.each do |body|
      role = body.starts_with?("||DabbleMeGPT||") ? "assistant" : "user"
      messages << {
        role: role,
        content: Nokogiri::HTML.parse(ReverseMarkdown.convert(body.gsub("||DabbleMeGPT||", ""), unknown_tags: :bypass)).text
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
