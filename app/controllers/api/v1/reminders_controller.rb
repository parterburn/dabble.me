# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/reminders?days=14 — what the app's daily push reminder shows on each of the
    # coming days (from today, in the journal's time zone): the entry to look back on, as Today
    # picks it. That's the first On This Day entry (PRO), or else the day's Rewind
    # (Api::Throwback). Days with nothing to look back on are left out.
    #
    # Which past entries can come up is the account's choice, the same for the push reminder and
    # the daily email (GET/PATCH /api/v1/email_schedule): none at all with past entries off,
    # none with the left-out words, and only the past year's (so no On This Day) without entries
    # over a year old. `email_hour` is the hour the daily email goes out, which the reminder's
    # time starts from.
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
        upcoming = current_user.send_past_entry == false ? [] : (0...days).filter_map { |offset| day_json(today + offset) }
        render json: { email_hour: current_user.send_time.hour, days: upcoming }
      end

      private

      # Entries the account's left-out words don't leave out.
      def kept_ids
        @kept_ids ||= current_user.random_entries.pluck(:id).to_set
      end

      def day_json(date)
        memories = []
        if current_user.is_pro? && current_user.way_back_past_entries != false
          memories = OnThisDay.entries(current_user, today: date).select { |entry| kept_ids.include?(entry.id) }.sort_by(&:date).reverse
        end
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
