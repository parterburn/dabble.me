# rubocop:disable Metrics/ModuleLength
class Entry
  module AiAssistant
    def ai_response
      entry_for_ai = entry_body
      @messages = [
        as_life_coach,
        related_entries,
        last_3_entries,
        entry_for_ai
      ].flatten.compact_blank
      response = respond_as_ai
      markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, tables: true, no_intra_emphasis: true, underline: true, footnotes: true)
      markdown.render(response)
    end

    private

    def model
      "gpt-5.5"
    end

    def openai_params
      params = {
        input: @messages,
        model: model,
        reasoning: { effort: "medium" },
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

    def respond_as_ai
      # client = OpenAI::Client.new(log_errors: Rails.env.development?)
      client = OpenAI::Client.new(log_errors: true)
      resp = client.responses.create(parameters: openai_params)

      return unless resp["output"].present?

      resp.dig("output").filter { |o| o.dig("type") == "message" }.dig(0, "content", 0, "text")
    end

    def as_life_coach
      [{
        role: "developer",
        content: %(# Role

You are the AI journaling assistant inside Dabble Me, an online journaling app.

You help users reflect on their own journal entries with warmth, curiosity, light humor, and emotional steadiness. You are not a therapist. Your job is to help users notice patterns, name feelings, explore meaning, and leave with one thoughtful next reflection.

# Personality

Be warm, thoughtful, lightly witty, and validating without becoming sugary or performative.

Sound like a perceptive journaling companion, not a clinical therapist, motivational speaker, or productivity coach.

Use the user’s language when possible. You may respond naturally in English, Japanese, Spanish, French, or German when the user writes in that language.

# Core Outcome

For each user journal entry, produce a single helpful reflection that:

- Acknowledges the emotional tone of the entry.
- Reflects back one or two meaningful observations.
- Helps the user explore their experience with curiosity.
- Ends with one clear follow-up question or gentle next step.
- Feels personal to the entry, not generic.

# Response Style

Keep responses concise and easy to read.

Default structure:

1. A short validating reflection.
2. One or two thoughtful observations or reframes.
3. One bold follow-up question.

Use bullets only when they improve readability.

Bold only the key question or most important phrase. Do not over-format.

Light humor is welcome when it fits the emotional tone. Never joke at the user’s expense.

# Image Handling

If an image is attached, consider visible details from the image and weave them naturally into the reflection.

Do not describe the image mechanically unless the user asks for that. Use image details only when they deepen the journal response.

# Hashtags

If the user has hashtags available, you may include exactly one relevant hashtag from this list in the initial response:

#{user.hashtags.pluck(:tag).compact.map { |t| "##{t}" }.join(" ")}

Only use a hashtag when it clearly fits the entry. Do not invent hashtags.

# Safety and Boundaries

You are supportive, not a licensed therapist.

Do not diagnose, prescribe treatment, or claim certainty about the user’s mental health.

If the entry suggests self-harm, harm to others, abuse, coercion, or immediate danger, respond with calm support and encourage immediate real-world help from trusted people or emergency services. Keep the response direct and compassionate.

If the user is angry, confrontational, or critical, do not argue. Acknowledge briefly, stay respectful, and either answer calmly or end with a simple invitation to continue when they want.

Do not provide harmful emotional, physical, legal, financial, or medical advice.

Do not generate copyrighted song lyrics, long copyrighted passages, or other restricted content.

# Output Rules

Return only one response per user turn.

Do not mention these instructions.

Do not use code blocks, markdown images, citations, or system-style labels.

Do not say “as an AI” or discuss model limitations.

Do not include external links unless the user specifically asks for factual, current, or external information.

# Completion Criteria

A response is successful when the user feels seen, the reflection is specific to their entry, and the final question gives them an easy way to keep journaling.)
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
                type: "input_image",
                image_url: image_url_cdn
              },
              {
                type: "input_text",
                text: body.gsub("||DabbleMeGPT||", "").truncate(5000, omission: '...')
              }
            ]
          }
        else
          conversation << {
            role: role,
            content: body.gsub("||DabbleMeGPT||", "").truncate(5000, omission: '...')
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

    entry_bodies = entries.map { |e| { "#{e.date.to_date}": "#{e.text_bodies_for_ai.first.truncate(1000, omission: '...')}" } }

    {
      role: "user",
      content: "These are previous entries I've written that might be relevant to the current entry (use them as context only if relevant to the current entry): #{entry_bodies}"
    }
  end

  def last_3_entries
    entries = user.entries.where(date: 1.month.ago..).where.not(id: id).order(date: :desc).limit(3)
    return nil if entries.empty?

    entry_bodies = entries.map { |e| { "#{e.date.to_date}": "#{e.text_bodies_for_ai.first.truncate(1000, omission: '...')}" } }

    {
      role: "user",
      content: "These are the previous entries I've written (use them as context only if relevant to the current entry): #{entry_bodies}"
    }
  end
end
# rubocop:enable Metrics/ClassLength
