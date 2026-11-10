# frozen_string_literal: true

module Api
  # How often each #hashtag appears in a user's entries since a date (one count per entry),
  # matched case-insensitively and shown in the spelling used most.
  class HashtagCounts
    def initialize(user, since:)
      @user = user
      @since = since
    end

    def top(limit)
      spellings = Hash.new { |hash, key| hash[key] = Hash.new(0) }
      user.entries.unscope(:order)
          .where(date: since.beginning_of_day..)
          .in_batches(of: 1000) do |batch|
        batch.pluck(:body).each do |body|
          Array(Entry.hashtags_in(body)).each { |tag| spellings[tag.downcase][tag] += 1 }
        end
      end

      spellings.map { |_key, counts| { tag: counts.max_by { |_tag, n| n }.first, count: counts.values.sum } }
               .sort_by { |item| [-item[:count], item[:tag].downcase] }
               .first(limit)
    end

    # The tags used most recently first (newest entries first), each in its latest spelling.
    def recent(limit)
      latest = {}
      user.entries.unscope(:order)
          .where(date: since.beginning_of_day..)
          .order(date: :desc, id: :desc)
          .pluck(:body)
          .each do |body|
        Array(Entry.hashtags_in(body)).each { |tag| latest[tag.downcase] ||= tag }
        break if latest.size >= limit
      end
      latest.values.first(limit).map { |tag| { tag: tag, count: 0 } }
    end

    private

    attr_reader :user, :since
  end
end
