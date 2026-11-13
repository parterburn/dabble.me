# frozen_string_literal: true

module Api
  # Numbers for the iOS app's Journal > Stats view: totals, streaks, a year of writing days,
  # recent months, and the past year's hashtags. Counts only; no entry text.
  class JournalStats
    HEATMAP_DAYS = 365
    RECENT_MONTHS = 12

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
        # The year the longest streak ended in (the app labels it "Streak • 2024").
        longest_streak_year: longest_streak_end&.year,
        entries_this_year: entries_this_year,
        # Every year with an entry, newest first, for the app's year menu ("2026 • 23 entries").
        entries_by_year: dates.group_by(&:year).map { |year, days| { year: year, count: days.size } }.sort_by { |row| -row[:year] },
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

    # Entries written in the current calendar year (the app's Today shows it, and the widget).
    def entries_this_year
      dates.count { |date| date.year == today.year }
    end

    # YYYY-MM-DD days with an entry in a calendar year, oldest first.
    def writing_days_in(year)
      dates.select { |date| date.year == year }.map(&:iso8601)
    end

    attr_reader :today

    private

    attr_reader :user

    # One date per entry (there's at most one entry per day), oldest first.
    def dates
      @dates ||= user.entries.unscope(:order).pluck(:date).compact.map(&:to_date).uniq.sort
    end

    # Summed from entries.word_count (kept current by Entry on save).
    def total_words
      user.entries.unscope(:order).sum(:word_count)
    end

    def longest_streak
      longest_run.first
    end

    # The last day of the longest streak (the earliest one, when two are as long).
    def longest_streak_end
      longest_run.last
    end

    # [days, last day] of the longest run of days in a row.
    def longest_run
      @longest_run ||= begin
        longest = run = 0
        last = nil
        dates.each_with_index do |date, index|
          run = index.positive? && dates[index - 1] == date - 1 ? run + 1 : 1
          longest, last = run, date if run > longest
        end
        [longest, last]
      end
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
