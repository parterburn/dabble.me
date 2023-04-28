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
        sleep 3
      end
    else
      process_entries(all_entries)
    end
  end

  private

  def process_entries(entries)
    tags = sentiment_tags(entries)
    if tags.present? && tags.is_a?(Array)
      entries.each do |entry|
        entry.sentiment = tags.shift
        entry.save
      end
    end
  end

  def sentiment_tags(entries)
    body = {
      options: {
        wait_for_model: true
      },
      inputs: entries.map { |e| e.text_body.first(MAX_ENTRY_SIZE) }
    }
    response = connection.post(AI_MODEL, body)

    response.body.map do |entry_emotions|
      data = entry_emotions.map do |emotion|
        if emotion.is_a?(Hash)
          next unless emotion["score"].to_f > SCORE_THRESHOLD

          emotion["label"]
        else
          raise(StandardError, "Unexpected response from Hugging Face API: #{response.body}")
        end
      end.reject(&:blank?)
      data.blank? ? ["unknown"] : data
    end
  end

  def connection
    @connection ||= Faraday.new(BASE_URL) do |f|
      f.request :json
      f.response :json
      f.request :authorization, "Bearer", ENV["HUGGING_FACE_API_KEY"]
    end
  end
end
