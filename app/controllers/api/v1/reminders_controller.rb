# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/reminders?days=14 — what the app's daily reminder shows on each of the coming
    # days (from today, in the journal's time zone): the entry to look back on, as Today picks it.
    # That's the first On This Day entry (PRO), or else the day's Rewind (Api::Throwback). Days
    # with nothing to look back on are left out. `email_hour` is the hour the daily email goes
    # out, which the reminder's time starts from.
    #
    #   { email_hour: 20, days: [{ date: "2026-11-12", kind: "on_this_day" | "rewind", count: 2,
    #                              entry: { id:, date:, excerpt:, image_url: } }] }
    #
    # The excerpt and photo are for a notification, which can show on a lock screen: the app only
    # uses them when the person has entry previews on.
    class RemindersController < BaseController
      MAX_DAYS = 30

      def show
        days = params[:days].to_s.match?(/\A\d+\z/) ? params[:days].to_i.clamp(1, MAX_DAYS) : 14
        today = OnThisDay.today_for(current_user)
        upcoming = (0...days).filter_map { |offset| day_json(today + offset) }
        render json: { email_hour: current_user.send_time.hour, days: upcoming }
      end

      private

      def day_json(date)
        memories = current_user.is_pro? ? OnThisDay.entries(current_user, today: date).sort_by(&:date).reverse : []
        entry = memories.first || Throwback.new(current_user, today: date).entry
        return nil unless entry

        summary = EntrySerializer.summary(entry)
        {
          date: date.iso8601,
          kind: memories.any? ? 'on_this_day' : 'rewind',
          count: [memories.size, 1].max,
          entry: summary.slice(:id, :date, :excerpt, :image_url)
        }
      end
    end
  end
end
