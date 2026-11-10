# frozen_string_literal: true

module Api
  # How often each #hashtag appears in a user's entries since a date (one count per entry),
  # matched case-insensitively and shown in the spelling used most.
  class HashtagCounts
    RECENT_PAGE_SIZE = 200

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
    # Reads bodies a page at a time and stops once it has enough tags, so a
    # long journal isn't loaded when the newest entries already hold them.
    def recent(limit)
      latest = {}
      newest_first = user.entries.unscope(:order)
                         .where(date: since.beginning_of_day..)
                         .order(date: :desc, id: :desc)
      offset = 0
      while latest.size < limit
        bodies = newest_first.offset(offset).limit(RECENT_PAGE_SIZE).pluck(:body)
        bodies.each do |body|
          Array(Entry.hashtags_in(body)).each { |tag| latest[tag.downcase] ||= tag }
        end
        break if bodies.size < RECENT_PAGE_SIZE

        offset += RECENT_PAGE_SIZE
      end
      latest.values.first(limit).map { |tag| { tag: tag, count: 0 } }
    end

    private

    attr_reader :user, :since
  end
end
