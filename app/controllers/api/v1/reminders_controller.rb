# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/reminders?days=14 — what the app's daily push reminder shows on each of the
    # coming days (from today, in the journal's time zone): the entry to look back on, as Today
    # picks it. That's the first On This Day entry (PRO), or else the day's Rewind
    # (Api::Throwback). Days with nothing to look back on are left out.
    #
    # Which past entries can come up is the account's choice, shared by the daily email, the push
    # reminder and the app's widget (GET/PATCH /api/v1/email_schedule): none with the left-out
    # words, and only the past year's (so no On This Day) without entries over a year old.
    #
    # Whether there's a past entry at all is each one's own switch. The account's
    # (`send_past_entry`) is the email's: the app has its own for the push reminder and the
    # widget, and asks with `all=1` for the days whatever the email's says. Without `all` (older
    # app builds, which had the one switch for everything) the days are empty when it's off.
    # `include_past_entries` says which way the email's is, for an app that hasn't been told yet
    # what its push reminder should do. `email_hour` is the hour the daily email goes out, which
    # the reminder's time starts from.
    #
    #   { email_hour: 20, include_past_entries: true,
    #     days: [{ date: "2026-11-12", kind: "on_this_day" | "rewind", count: 2,
    #              entry: { id:, date:, excerpt:, image_url: },
    #              entries: [{ id:, date:, excerpt:, image_url: }, ...] }] }
    #
    # `entries` is every entry the day has to look back on, the newest year first and `entry`
    # among them, up to MAX_ENTRIES: all of On This Day's, or the one Rewind. The app's widget
    # shows them in turn through the day. (An older app build reads `entry` alone.)
    #
    # The excerpt and photo are for a notification, which can show on a lock screen: the app only
    # uses them when the person has entry previews on.
    class RemindersController < BaseController
      MAX_DAYS = 30
      MAX_ENTRIES = 8

      def show
        days = params[:days].to_s.match?(/\A\d+\z/) ? params[:days].to_i.clamp(1, MAX_DAYS) : 14
        today = OnThisDay.today_for(current_user)
        email_includes = current_user.send_past_entry != false
        every = ActiveModel::Type::Boolean.new.cast(params[:all])
        upcoming = every || email_includes ? (0...days).filter_map { |offset| day_json(today + offset) } : []
        render json: { email_hour: current_user.send_time.hour, include_past_entries: email_includes, days: upcoming }
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

        {
          date: date.iso8601,
          kind: memories.any? ? 'on_this_day' : 'rewind',
          count: [memories.size, 1].max,
          entry: look_back_json(entry),
          entries: (memories.presence || [entry]).first(MAX_ENTRIES).map { |memory| look_back_json(memory) }
        }
      end

      def look_back_json(entry)
        summary = EntrySerializer.summary(entry)
        # A photo still uploading has a stand-in picture for an address: not for a widget or a
        # notification, which keep what they're given.
        summary[:image_url] = nil if summary[:image_processing]
        summary.slice(:id, :date, :excerpt, :image_url)
      end
    end
  end
end
