class Entry::AiTagger
  SCORE_THRESHOLD = 0.5 # higher = higher confidence in match
  BASE_URL = "https://api-inference.huggingface.co".freeze
  AI_MODEL = "/models/j-hartmann/emotion-english-distilroberta-base".freeze
  MAX_ENTRY_SIZE = 512

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

  def tag(entries)
    all_entries = Array(entries).flatten
    if all_entries.count > 100
      all_entries.each_slice(100) do |entries_slice|
        process_entries(entries_slice)
      end
    else
      process_entries(all_entries)
    end
  end

  private

  def process_entries(entries)
    emotion_hash = sentiment_tags(entries)

    emotion_hash.each do |entry_id, tags|
      entry = entries.find { |e| e.id == entry_id }
      next unless entry.present?

      entry.sentiment = tags
      entry.save
    end
  end

  def sentiment_tags(entries)
    body = {
      inputs: entries.map { |e| e.text_bodies_for_ai.first.first(MAX_ENTRY_SIZE) }
    }
    response = connection.post(AI_MODEL, body)

    if response.body.is_a?(Hash) && response.body["error"].present?
      Sentry.capture_message("Hugging Face Error", level: :info, extra: { error: response.body["error"] })
      return nil
    elsif !response.body.is_a?(Hash)
      Sentry.capture_message("Hugging Face Error", level: :info, extra: { error: response.body })
      return nil
    end

    emotion_hash = {}
    response.body.map do |entry_emotions|
      emotion_hash[entries[i].id] ||= []
      error = false
      entry_emotions.each_with_index do |emotion, i|
        if emotion.is_a?(Hash) && emotion["score"] && emotion["score"].to_f > SCORE_THRESHOLD
          emotion_hash[entries[i].id] << emotion["label"]
        elsif !emotion.is_a?(Hash) || (emotion.is_a?(Hash) && emotion["score"].blank?)
          error = true
          Sentry.capture_message("Hugging Face Error", level: :info, extra: { error: emotion })
        end
      end

      emotion_hash[entries[i].id] << ["unknown"] unless error # only add unknown if no emotions are higher than threshold
    end
    emotion_hash
  end

  def connection
    @connection ||= Faraday.new(BASE_URL) do |f|
      f.request :json
      f.response :json
      f.request :authorization, "Bearer", ENV["HUGGING_FACE_API_KEY"]
    end
  end
end
