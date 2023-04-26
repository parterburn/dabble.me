class Entry::AiTagger
  SCORE_THRESHOLD = 0.5 # higher = higher confidence in match
  BASE_URL = "https://api-inference.huggingface.co".freeze
  AI_MODEL = "/models/j-hartmann/emotion-english-distilroberta-base".freeze
  MAX_ENTRY_SIZE = 512

  def tag(entries)
    @entries = Array(entries)
    tags = sentiment_tags
    @entries.each do |entry|
      entry.sentiment = tags.shift
      entry.save
    end
  end

  private

  def entry_body
    { "inputs": @entries.map { |e| e.text_body.first(MAX_ENTRY_SIZE) } }
  end

  def sentiment_tags
    response = connection.post(AI_MODEL, entry_body)

    response.body.map do |entry_emotions|
      data = entry_emotions.map do |emotion|
        next unless emotion["score"].to_f > SCORE_THRESHOLD

        emotion["label"]
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
