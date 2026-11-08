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
          .where("entries.body ~ '#[A-Za-z0-9_]'")
          .find_each do |entry|
        Array(entry.hashtags).each { |tag| spellings[tag.downcase][tag] += 1 }
      end

      spellings.map { |_key, counts| { tag: counts.max_by { |_tag, n| n }.first, count: counts.values.sum } }
               .sort_by { |item| [-item[:count], item[:tag].downcase] }
               .first(limit)
    end

    private

    attr_reader :user, :since
  end
end
