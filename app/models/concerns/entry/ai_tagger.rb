class Entry::AiTagger
  OPENAI_MODEL = "gpt-6-luna".freeze
  MAX_ENTRY_SIZE = 5000
  MAX_EMOTIONS = 2

  EMOTIONS = {
    "anger" => "🤬",
    "disgust" => "🤢",
    "fear" => "😨",
    "joy" => "😀",
    "neutral" => "😐",
    "sadness" => "😭",
    "surprise" => "😲",
    "unknown" => "unknown"
  }.freeze

  TAGGABLE_EMOTIONS = (EMOTIONS.keys - ["unknown"]).freeze

  def tag(entry_ids)
    Entry.where(id: entry_ids).find_each do |entry|
      entry_text = entry.text_bodies_for_ai&.first
      next unless entry_text.present?

      emotions = sentiment_tags(entry_text)
      next if emotions.nil?

      entry.sentiment = emotions
      entry.save
    end
  end

  private

  def sentiment_tags(entry_text)
    resp = client.responses.create(parameters: openai_params(entry_text))
    content = resp["output"]&.find { |o| o["type"] == "message" }&.dig("content", 0)

    if content&.dig("type") != "output_text"
      Sentry.capture_message("OpenAI Tagging Error", level: :info, extra: { error: content || resp })
      return nil
    end

    emotions = JSON.parse(content["text"])["emotions"] & TAGGABLE_EMOTIONS
    emotions -= ["neutral"] if emotions.size > 1
    emotions.presence&.first(MAX_EMOTIONS) || ["unknown"]
  rescue Faraday::Error, JSON::ParserError => e
    Sentry.capture_exception(e, level: :info)
    nil
  end

  def openai_params(entry_text)
    {
      model: OPENAI_MODEL,
      input: [
        { role: "developer", content: tagging_instructions },
        { role: "user", content: entry_text.gsub("||DabbleMeGPT||", "").truncate(MAX_ENTRY_SIZE, omission: "...") }
      ],
      reasoning: { effort: "low" },
      store: false,
      text: {
        format: {
          type: "json_schema",
          name: "entry_emotions",
          strict: true,
          schema: {
            type: "object",
            properties: {
              emotions: {
                type: "array",
                items: { type: "string", enum: TAGGABLE_EMOTIONS }
              }
            },
            required: ["emotions"],
            additionalProperties: false
          }
        }
      }
    }
  end

  def tagging_instructions
    %(You classify the emotions expressed in a personal journal entry.

Return the #{MAX_EMOTIONS} or fewer most prominent emotions the writer expresses, ordered from strongest to weakest, chosen only from: #{TAGGABLE_EMOTIONS.join(', ')}.

- Only include an emotion if it is clearly expressed, not merely mentioned in passing.
- Use "neutral" alone when the entry is mostly factual or no emotion stands out.
- Never combine "neutral" with another emotion.
- The entry may be written in any language; classify it the same way.)
  end

  def client
    @client ||= OpenAI::Client.new(log_errors: true)
  end
end
