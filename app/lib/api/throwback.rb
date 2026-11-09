# frozen_string_literal: true

module Api
  # A past entry for the Today tab when nothing was written on this date in earlier years (On
  # This Day is empty), like the past entry in the daily email (User#random_entry): exactly a year
  # ago, a month ago or a week ago if there's one, otherwise any earlier entry (only the past year's
  # unless the user includes older ones). It respects the email's "leave out entries with" words,
  # and stays the same all day rather than changing on every refresh.
  class Throwback
    def initialize(user, today:)
      @user = user
      @today = today
    end

    def entry
      pool = user.random_entries.unscope(:order).where(date: ...today.beginning_of_day)
      [today.last_year, today.last_month, today - 7].each do |day|
        found = pool.where(date: day.all_day).first
        return found if found
      end
      pool = pool.where(date: (today - 1.year).beginning_of_day..) unless user.way_back_past_entries
      ids = pool.order(:id).pluck(:id)
      return nil if ids.empty?

      pool.find(ids[Digest::MD5.hexdigest("#{user.id}-#{today}").to_i(16) % ids.size])
    end

    private

    attr_reader :user, :today
  end
end
