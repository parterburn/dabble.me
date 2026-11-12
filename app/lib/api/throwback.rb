# frozen_string_literal: true

module Api
  # A past entry for the Today tab when nothing was written on this date in earlier years (On
  # This Day is empty), like the past entry in the daily email (User#random_entry): the last leap
  # day on Feb 29, exactly a year ago, a month ago or a week ago if there's one, otherwise any
  # earlier entry (the past year's unless the user includes older ones; older ones anyway when the
  # past year has none, so even a single old entry comes back). It respects the email's "leave out
  # entries with" words, and stays the same all day rather than changing on every refresh.
  class Throwback
    # `pool` and `way_back` stand in for the email's own choices (User#random_entries, minus its
    # left-out words; User#way_back_past_entries) where the app's push reminder has its own.
    def initialize(user, today:, pool: nil, way_back: nil)
      @user = user
      @today = today
      @pool = pool
      @way_back = way_back
    end

    def entry
      pool = (@pool || user.random_entries).unscope(:order).where(date: ...today.beginning_of_day)
      exact_days.each do |day|
        found = pool.where(date: day.all_day).first
        return found if found
      end
      recent = pool.where(date: (today - 1.year).beginning_of_day..)
      way_back = @way_back.nil? ? user.way_back_past_entries : @way_back
      pick(way_back || !recent.exists? ? pool : recent)
    end

    private

    attr_reader :user, :today

    def exact_days
      days = [today.last_year, today.last_month, today - 7]
      days.unshift(Date.new(today.year - 4, 2, 29)) if today.month == 2 && today.day == 29
      days
    end

    # The same entry all day for this user.
    def pick(pool)
      ids = pool.order(:id).pluck(:id)
      return nil if ids.empty?

      pool.find(ids[Digest::MD5.hexdigest("#{user.id}-#{today}").to_i(16) % ids.size])
    end
  end
end
