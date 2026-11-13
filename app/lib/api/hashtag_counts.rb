# frozen_string_literal: true

module Api
  # How often each #hashtag appears in a user's entries since a date, or between two (one count
  # per entry),
  # matched case-insensitively. An entry that spells a tag two ways counts once, in its first
  # spelling.
  #
  # #top shows each tag in the spelling used in the most entries. A tie goes to the spelling used
  # most recently: the one whose newest entry is latest by date, then by id, the order #recent
  # reads entries in. Rows come back in no set order, so the tie-break can't depend on which
  # spelling is read first.
  class HashtagCounts
    RECENT_PAGE_SIZE = 200

    # `upto` (a date, included) ends the span: a calendar year's tags, say.
    def initialize(user, since:, upto: nil)
      @user = user
      @since = since
      @upto = upto
    end

    def top(limit)
      # spellings["run"]["Run"] = [entries using "Run", [date, id] of the newest of them]
      spellings = Hash.new { |hash, key| hash[key] = {} }
      entries_since.in_batches(of: 1000) do |batch|
        batch.pluck(:date, :id, :body).each do |date, id, body|
          tags_in(body).each do |tag|
            count, newest = spellings[tag.downcase][tag]
            spellings[tag.downcase][tag] = [count.to_i + 1, [newest, [date, id]].compact.max]
          end
        end
      end

      spellings.map { |_key, uses| { tag: uses.max_by { |_tag, use| use }.first, count: uses.values.sum(&:first) } }
               .sort_by { |item| [-item[:count], item[:tag].downcase] }
               .first(limit)
    end

    # The tags used most recently first (newest entries first), each in its latest spelling.
    # Reads bodies a page at a time and stops once it has enough tags, so a
    # long journal isn't loaded when the newest entries already hold them.
    def recent(limit)
      latest = {}
      newest_first = entries_since.order(date: :desc, id: :desc)
      offset = 0
      while latest.size < limit
        bodies = newest_first.offset(offset).limit(RECENT_PAGE_SIZE).pluck(:body)
        bodies.each do |body|
          tags_in(body).each { |tag| latest[tag.downcase] ||= tag }
        end
        break if bodies.size < RECENT_PAGE_SIZE

        offset += RECENT_PAGE_SIZE
      end
      latest.values.first(limit).map { |tag| { tag: tag, count: 0 } }
    end

    private

    attr_reader :user, :since, :upto

    def entries_since
      user.entries.unscope(:order).where(date: since.beginning_of_day..upto&.end_of_day)
    end

    def tags_in(body)
      Array(Entry.hashtags_in(body)).uniq(&:downcase)
    end
  end
end
