module EntryService
  def create!(author, params)
    entry = EntryMutator.create!(author, params)

    entry.songs = SpotifyManager.find_songs

    tweet_in_body = has_tweet_link_inside?(entry.boby)
    TwitterManager.reply(tweet_in_body, existing_entry.url) if tweet_in_body

    entry
  end

  def merge!(existing_entry, params)
    original_entry_tweet = has_tweet_link_inside?(existing_entry.body)

    existing_entry = EntryMutator.merge!(existing_entry, params)

    existing_entry.inspiration_id = params[:inspiration_id] if params[:inspiration_id].present?
    if existing_entry.image_url_cdn.blank? && params[:image].present?
      existing_entry.image = params[:image]
    end

    existing_entry.save

    entry.songs = SpotifyManager.find_songs

    if !original_entry_tweet
      tweet_in_body = has_tweet_link_inside?(params[:entry])
      TwitterManager.reply(tweet_in_body, existing_entry.url) if tweet_in_body
    end

    existing_entry
  end

  def has_tweet_link_inside?(text)
    'https://twitter.com/inem/status/1325000674229301248' if text.match? 'twitter.com'
  end
end