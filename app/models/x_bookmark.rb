class XBookmark < ActiveRecord::Base
  belongs_to :user

  validates :tweet_id, presence: true, uniqueness: { scope: :user_id }

  scope :recent, -> { order(tweeted_at: :desc) }
  scope :since, ->(time) { where('tweeted_at >= ?', time) }

  def tweet_url
    url || "https://x.com/#{author_username}/status/#{tweet_id}"
  end

  # Syncs latest 5 bookmarks from X API for a user. Skips duplicates.
  # Returns count of new bookmarks saved.
  def self.sync_for_user!(user, max_results: 5)
    client = XApiClient.new(user: user)
    result = client.bookmarks(max_results: max_results)
    tweets = result['data']
    return 0 unless tweets.present?

    authors = (result.dig('includes', 'users') || []).index_by { |u| u['id'] }
    new_count = 0

    tweets.each do |tweet|
      next if user.x_bookmarks.exists?(tweet_id: tweet['id'])

      author = authors[tweet['author_id']] || {}
      user.x_bookmarks.create!(
        tweet_id: tweet['id'],
        author_id: tweet['author_id'],
        author_username: author['username'],
        author_name: author['name'],
        text: tweet['text'],
        tweeted_at: tweet['created_at'],
        url: "https://x.com/#{author['username']}/status/#{tweet['id']}",
        entities: tweet['entities'] || {},
        public_metrics: tweet['public_metrics'] || {}
      )
      new_count += 1
    end

    new_count
  end
end
