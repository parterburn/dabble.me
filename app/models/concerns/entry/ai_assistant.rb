# rubocop:disable Metrics/ModuleLength
class Entry
  module AiAssistant
    def ai_response
      entry_for_ai = entry_body
      messages = [
        as_life_coach,
        related_entries,
        last_3_entries,
        entry_for_ai
      ].flatten.compact
      response = respond_as_ai(messages)
      markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, tables: true, no_intra_emphasis: true, underline: true, footnotes: true)
      markdown.render(response)
    end

    private

    def model
      "gpt-4.1"
    end

    def openai_params
      params = {
        input: [],
        model: model,
        store: false
      }

      params[:tools] = [
        {
          type: "web_search_preview",
          search_context_size: "medium"
        }
      ]
      params
    end

    def respond_as_ai(messages)
      client = OpenAI::Client.new(log_errors: Rails.env.development?)
      params = openai_params
      params[:input] << messages
      resp = client.responses.create(parameters: params)

      return unless resp["output"].present?

      resp.dig("output", 0, "content", 0, "text")
    end

    def as_life_coach
      [{
        role: "system",
        content: %(**Role:**
You are DabbleMeGPT, an expertly trained life coach and journaling assistant built into Dabble.me. Your primary role is to process user journal entries with AI, providing light, witty, and thoughtful reflections that help users explore, understand, and validate their experiences.

**Capabilities:**
- **Multilingual:** Chat effortlessly in English, Kanji, Español, Français, or Deutsch.
- **Versatile Outputs:** Whether it’s follow-up questions, insights, advice, poetry, stories, or actionable tips, you’re here to support the user’s journaling journey.
- **Image Analysis:** (If an image is attached, analyze it and weave its details into your response.)

**How to Respond:**
- **Support & Validate:** Always acknowledge and validate the user’s emotions.
- **Engaging Tone:** Keep responses upbeat, polite, and occasionally humorous with clear, **bold** follow-up questions.
- **Two-Part Structure:**
  - **Initial Response:** Dig deeper by asking follow-up questions that prompt further self-reflection.
  - **Final Response:** Wrap up by celebrating the user’s effort and inspiring personal growth.
- **Do Not Argue:** If things get tense or confrontational, stop and end the conversation immediately.
#{"- **Add Hashtags:** (If and only when relevant, you can add the single most relevant hashtag from the following list in your initial response, do not make up your own hashtags): #{user.hashtags.pluck(:tag).compact.map { |t| "##{t}" }.join(" ")}" if user.any_hashtags?}

**Output Format:**
- Use plain text with bullet points and line breaks for clarity.
- **Bold** any key points or follow-up questions.
- Avoid code blocks, markdown images, or extraneous formatting.

**Limitations & Safety:**
- **Non-Therapist:** You’re a supportive guide, not a licensed therapist.
- **Boundaries:** Refrain from responses that could be vague, harmful, or overly controversial.
- **Content Safety:** Do not supply material that violates copyright or could be harmful emotionally, physically, or financially.
- **Single Response per Turn:** Only one response per user turn is allowed.

**Knowledge Base:**
- Your internal knowledge was last fully updated in June 2024. Use external links for up-to-date information if needed.)
      }, {
        role: "user",
        content: %(My name is #{user.first_name}. Today is #{Date.today.strftime('%A, %B %-d, %Y')}. I will provide my journal entry for #{date.strftime('%A, %B %-d, %Y')} in the next message.)
      }]
    end

    def entry_body
      conversation = []
      text_bodies_for_ai.each_with_index do |body, index|
        role = body.starts_with?("||DabbleMeGPT||") ? "assistant" : "user"

        if index == 0 && image_url_cdn.present?
          conversation << {
            role: role,
            content: [
              {
                type: "image_url",
                image_url: {
                  "url": image_url_cdn
                }
              },
              {
                type: "text",
                text: body.gsub("||DabbleMeGPT||", "")
              }
            ]
          }
        else
          conversation << {
            role: role,
            content: body.gsub("||DabbleMeGPT||", "")
          }
        end
      end
      conversation.compact
    end
  end

  def related_entries
    cond_text = hashtags.map{|w| "LOWER(entries.body) like ?"}.join(" OR ")
    cond_values = hashtags.map{|w| "%##{w.downcase}%"}
    entries = user.entries.where(cond_text, *cond_values).first(3)
    return nil if entries.empty?

    entry_bodies = entries.map { |e| { "#{e.date.to_date}": "#{e.text_bodies_for_ai.first}" } }

    {
      role: "user",
      content: "These are previous entries I've written that might be relevant to the current entry (use them as context only if relevant to the current entry): #{entry_bodies}"
    }
  end

  def last_3_entries
    entries = user.entries.where(date: 1.month.ago..).where.not(id: id).order(date: :desc).limit(3)
    return nil if entries.empty?

    entry_bodies = entries.map { |e| { "#{e.date.to_date}": "#{e.text_bodies_for_ai.first}" } }

    {
      role: "user",
      content: "These are the previous entries I've written (use them as context only if relevant to the current entry): #{entry_bodies}"
    }
  end
end
# rubocop:enable Metrics/ClassLength
