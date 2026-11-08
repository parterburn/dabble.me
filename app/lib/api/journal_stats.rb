# frozen_string_literal: true

module Api
  # Numbers for the iOS app's Journal > Stats view: totals, streaks, a year of writing days,
  # recent months, and the past year's hashtags. Counts only; no entry text.
  class JournalStats
    HEATMAP_DAYS = 365
    RECENT_MONTHS = 12

    # Words in an entry: tags and HTML entities become spaces, then whitespace-separated runs count.
    WORD_COUNT_SQL = <<~SQL.squish
      COALESCE(SUM(
        CASE WHEN btrim(stripped) = '' THEN 0
             ELSE array_length(regexp_split_to_array(btrim(stripped), '\\s+'), 1) END
      ), 0)
    SQL

    def initialize(user, today: OnThisDay.today_for(user))
      @user = user
      @today = today
    end

    def as_json(*)
      {
        total_entries: dates.size,
        total_words: total_words,
        photo_entries: user.entries.where("image IS NOT NULL AND image != ''").count,
        first_entry_date: dates.first&.iso8601,
        current_streak: current_streak,
        longest_streak: longest_streak,
        entries_this_year: dates.count { |date| date.year == today.year },
        writing_days: dates.select { |date| date > today - HEATMAP_DAYS && date <= today }.map(&:iso8601),
        months: recent_months,
        busiest_weekday: busiest_weekday,
        top_hashtags: HashtagCounts.new(user, since: today - 1.year).top(10)
      }
    end

    # Days in a row up to today, or up to yesterday while today is still unwritten.
    def current_streak
      set = dates.to_set
      day = set.include?(today) ? today : today - 1
      streak = 0
      while set.include?(day)
        streak += 1
        day -= 1
      end
      streak
    end

    private

    attr_reader :user, :today

    # One date per entry (there's at most one entry per day), oldest first.
    def dates
      @dates ||= user.entries.unscope(:order).pluck(:date).compact.map(&:to_date).uniq.sort
    end

    def total_words
      stripped = user.entries.unscope(:order).select(
        Arel.sql("regexp_replace(regexp_replace(COALESCE(body, ''), '<[^>]*>', ' ', 'g'), '&[#a-zA-Z0-9]+;', ' ', 'g') AS stripped")
      )
      Entry.connection.select_value("SELECT #{WORD_COUNT_SQL} FROM (#{stripped.to_sql}) AS bodies").to_i
    end

    def longest_streak
      longest = run = 0
      dates.each_with_index do |date, index|
        run = index.positive? && dates[index - 1] == date - 1 ? run + 1 : 1
        longest = [longest, run].max
      end
      longest
    end

    def recent_months
      counts = dates.group_by { |date| [date.year, date.month] }.transform_values(&:size)
      (0...RECENT_MONTHS).map do |offset|
        month = today.beginning_of_month << offset
        { year: month.year, month: month.month, count: counts.fetch([month.year, month.month], 0) }
      end.reverse
    end

    def busiest_weekday
      return nil if dates.empty?

      Date::DAYNAMES[dates.group_by(&:wday).max_by { |_wday, days| days.size }.first]
    end
  end
end
