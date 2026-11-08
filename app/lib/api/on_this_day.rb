# frozen_string_literal: true

module Api
  # Entries from today's calendar date in earlier years (the user's journal time zone),
  # using the same day ranges as the web sidebar's "years ago" list.
  module OnThisDay
    module_function

    def today_for(user)
      Time.current.in_time_zone(user.send_timezone).to_date
    end

    def entries(user, today: today_for(user))
      first_year = user.entries.minimum(:date)&.year || today.year
      day_ranges = (1..(today.year - first_year)).map { |years| (today - years.years).all_day }
      scope = day_ranges.map { |range| user.entries.where(date: range) }.reduce(:or)
      scope ? scope.to_a : []
    end
  end
end
