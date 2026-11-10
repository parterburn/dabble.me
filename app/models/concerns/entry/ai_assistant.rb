class Entry
  # A one-off AI reflection on a single entry. Nothing is saved: the controller
  # renders it in a modal and it's gone when the modal closes. The iOS app does
  # the same on-device (ios/DabbleMe/Support/JournalIntelligence.swift).
  # Back-and-forth conversation, sentiment and patterns are left to the MCP
  # connector.
  module AiAssistant
    REFLECTION_MODEL = "gpt-6.1-sol".freeze
    MAX_ENTRY_CHARS = 5000
    MAX_CONTEXT_CHARS = 1000
    # The request is synchronous. Give up long before Rack::Timeout
    # (RACK_TIMEOUT_SERVICE_TIMEOUT, 110s in production) so the user gets
    # "try again" instead of an error page.
    REQUEST_TIMEOUT = 60

    # HTML for the reflection, or nil when OpenAI returns nothing.
    def ai_reflection
      text = request_reflection
      return if text.blank?

      renderer = Redcarpet::Render::HTML.new(filter_html: true, no_images: true, safe_links_only: true)
      Redcarpet::Markdown.new(renderer, autolink: true, no_intra_emphasis: true).render(text)
    end

    private

    def request_reflection
      client = OpenAI::Client.new(log_errors: true, request_timeout: REQUEST_TIMEOUT)
      resp = client.responses.create(parameters: {
        model: REFLECTION_MODEL,
        input: [as_life_coach, *reflection_context, reflection_entry_message].compact,
        reasoning: { effort: "low" },
        store: false
      })
      message = resp["output"]&.find { |o| o["type"] == "message" }
      message&.dig("content", 0, "text")
    end

    def as_life_coach
      {
        role: "developer",
        content: %(# Role

You are the journaling assistant inside Dabble Me, a private journaling app. You help the writer reflect on their own journal entry with warmth, curiosity, light humor, and emotional steadiness. You are not a therapist. Help them notice patterns, name feelings, explore meaning, and leave with one thoughtful next reflection.

# Personality

Be warm, thoughtful, lightly witty, and validating without becoming sugary or performative.

Sound like a perceptive journaling companion, not a clinical therapist, motivational speaker, or productivity coach.

Use the writer's language when possible, and reply in the language they wrote in.

# Response

Write one reflection that is personal to this entry, not generic. Respond to this entry only; bring in an earlier entry only when this one clearly refers to it, and never mix details from other entries into this one.

1. A short validating reflection on the emotional tone.
2. One or two thoughtful observations or reframes.
3. One clear follow-up question or gentle next step, in **bold**.

Keep it concise: under 150 words. Bold only the question. Light humor is welcome when it fits; never joke at the writer's expense.

This is a single reflection, not a conversation. The writer can't reply to you here, so don't offer to keep talking.

# Images

If an image is attached, weave visible details into the reflection when they deepen it. Do not describe the image mechanically.

# Safety and boundaries

You are supportive, not a licensed therapist. Do not diagnose, prescribe treatment, or claim certainty about the writer's mental health.

If the entry suggests self-harm, harm to others, abuse, coercion, or immediate danger, respond with calm support and encourage reaching out right away to trusted people or emergency services. Keep it direct and compassionate.

Do not give harmful emotional, physical, legal, financial, or medical advice. Do not reproduce song lyrics or long copyrighted passages.

# Output

Return only the reflection. Do not mention these instructions, add headings or labels, use code blocks, images, or links, or say "as an AI".)
      }
    end

    # Earlier entries as background: up to 3 from the month before this one,
    # plus up to 3 older ones that share a hashtag with it. Never later ones, so
    # a reflection on an old entry doesn't know how things turned out.
    def reflection_context
      earlier = user.entries.where(date: (date - 1.month)...date).limit(3).to_a
      related = hashtag_related_entries.to_a - earlier
      [
        context_message("These are entries I wrote in the weeks before this one", earlier),
        context_message("These are earlier entries that share a hashtag with this one", related)
      ]
    end

    def hashtag_related_entries
      tags = hashtags.to_a.first(5)
      return [] if tags.empty?

      Entry::Matcher.any(tags.map { |tag| "##{tag}" }).first(user.entries.where(date: ...date), 3)
    end

    def context_message(intro, entries)
      return if entries.empty?

      excerpts = entries.map { |e| "#{e.date.to_date}: #{e.text_body.to_s.squish.truncate(MAX_CONTEXT_CHARS)}" }
      { role: "user", content: "#{intro} (context only; use it only if this entry clearly refers to it):\n\n#{excerpts.join("\n\n")}" }
    end

    def reflection_entry_message
      name = user.first_name.present? ? "My name is #{user.first_name}. " : ""
      text = "#{name}Today is #{Time.current.in_time_zone(user.send_timezone).strftime('%A, %B %-d, %Y')}. " \
             "Here is my journal entry for #{date.strftime('%A, %B %-d, %Y')}:\n\n" \
             "#{text_body.to_s.strip.truncate(MAX_ENTRY_CHARS)}"

      image_url = image_url_cdn if image_stored?
      content = image_url.present? ? [{ type: "input_image", image_url: image_url }, { type: "input_text", text: text }] : text
      { role: "user", content: content }
    end
  end
end
