class Entry
  # A one-off AI reflection on a single entry. Nothing is saved: the controller
  # renders it in a modal and it's gone when the modal closes. The iOS app does
  # the same on-device (ios/DabbleMe/Support/JournalIntelligence.swift).
  # Back-and-forth conversation, sentiment and patterns are left to the MCP
  # connector.
  module AiAssistant
    MAX_ENTRY_CHARS = 5000
    MAX_CONTEXT_CHARS = 1000
    # The request is synchronous. Give up long before Rack::Timeout
    # (RACK_TIMEOUT_SERVICE_TIMEOUT, 110s in production) so the user gets
    # "try again" instead of an error page. No retries, for the same reason.
    REQUEST_TIMEOUT = 60
    # A reflection is under 150 words. Room for that plus the model's thinking.
    MAX_OUTPUT_TOKENS = 8_000
    # Low effort keeps a short reflection quick; it needs no long deliberation.
    EFFORT = "low"
    # Models that accept Anthropic's server-side refusal fallback. If a safety
    # classifier declines an entry, another model writes the reflection instead
    # of the writer getting nothing. Other models don't take the parameter.
    REFUSAL_FALLBACK_MODELS = /\Aclaude-(opus-5(-5)?|sonnet-5-5|fable-5-[12])\z/
    REFUSAL_FALLBACK_BETA = "server-side-fallback-2026-07-01"

    # The Claude model that writes reflections, e.g. claude-opus-5-5. Set in
    # the environment (REFLECTION_MODEL) so it can change without a code change.
    def self.model
      ENV["REFLECTION_MODEL"].presence
    end

    # Reflections are offered only when a model and an Anthropic key are set.
    def self.configured?
      model.present? && RubyLLM.config.anthropic_api_key.present?
    end

    # HTML for the reflection, or nil when the model returns nothing.
    def ai_reflection
      text = request_reflection
      return if text.blank?

      renderer = Redcarpet::Render::HTML.new(filter_html: true, no_images: true, safe_links_only: true)
      Redcarpet::Markdown.new(renderer, autolink: true, no_intra_emphasis: true).render(text)
    end

    private

    def request_reflection
      model = AiAssistant.model
      llm = RubyLLM.context do |config|
        config.request_timeout = REQUEST_TIMEOUT
        config.max_retries = 0
      end
      # assume_model_exists: any Claude model named in REFLECTION_MODEL works,
      # even one newer than RubyLLM's built-in model list.
      chat = llm.chat(model: model, provider: :anthropic, assume_model_exists: true)
                .with_instructions(reflection_instructions)
                .with_max_output_tokens(MAX_OUTPUT_TOKENS)
      options = { output_config: { effort: EFFORT } }
      if model.match?(REFUSAL_FALLBACK_MODELS)
        options[:fallbacks] = "default"
        chat.with_headers("anthropic-beta" => REFUSAL_FALLBACK_BETA)
      end
      chat.with_provider_options(options)

      reflection_context.compact.each { |context| chat.add_message(role: :user, content: context) }
      text, image_url = reflection_entry_message
      response = chat.ask(text, with: image_url)
      AiUsage.record(user: user, response: response, requested_model: model)
      response.content
    end

    def reflection_instructions
      %(# Role

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
      "#{intro} (context only; use it only if this entry clearly refers to it):\n\n#{excerpts.join("\n\n")}"
    end

    # The entry's text, and its photo's URL when it has one. Anthropic fetches
    # the photo from the URL; it isn't downloaded and re-sent from here.
    def reflection_entry_message
      name = user.first_name.present? ? "My name is #{user.first_name}. " : ""
      text = "#{name}Today is #{Time.current.in_time_zone(user.send_timezone).strftime('%A, %B %-d, %Y')}. " \
             "Here is my journal entry for #{date.strftime('%A, %B %-d, %Y')}:\n\n" \
             "#{text_body.to_s.strip.truncate(MAX_ENTRY_CHARS)}"

      [text, (image_url_cdn if image_stored?).presence]
    end
  end
end
