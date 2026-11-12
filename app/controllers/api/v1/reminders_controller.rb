# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/reminders?days=14&filter=work,doctor&include_old=0 — what the app's daily
    # reminder shows on each of the coming days (from today, in the journal's time zone): the
    # entry to look back on, as Today picks it. That's the first On This Day entry (PRO), or else
    # the day's Rewind (Api::Throwback). Days with nothing to look back on are left out.
    #
    # The reminder has its own choices of past entries, like the email's (PRO): `filter` is words
    # that leave entries out (comma-separated; an empty one leaves none out), and `include_old=0`
    # keeps to the past year (so no On This Day). Without them, the email's settings apply.
    # `email_hour` is the hour the daily email goes out, which the reminder's time starts from.
    #
    #   { email_hour: 20, filtered_count: 3,
    #     days: [{ date: "2026-11-12", kind: "on_this_day" | "rewind", count: 2,
    #              entry: { id:, date:, excerpt:, image_url: } }] }
    #
    # The excerpt and photo are for a notification, which can show on a lock screen: the app only
    # uses them when the person has entry previews on.
    class RemindersController < BaseController
      MAX_DAYS = 30

      def show
        days = params[:days].to_s.match?(/\A\d+\z/) ? params[:days].to_i.clamp(1, MAX_DAYS) : 14
        today = OnThisDay.today_for(current_user)
        upcoming = (0...days).filter_map { |offset| day_json(today + offset) }
        render json: { email_hour: current_user.send_time.hour, filtered_count: left_out_ids&.size.to_i, days: upcoming }
      end

      private

      # The reminder's own left-out words (PRO), when the app sends them.
      def own_filter?
        current_user.is_pro? && params.key?(:filter)
      end

      # Entries its words leave out, or nil when the email's words apply.
      def left_out_ids
        return nil unless own_filter?

        @left_out_ids ||= begin
          words = params[:filter].to_s.split(',').map(&:strip).compact_blank
          matcher = words.any? ? Entry::Matcher.any(words) : nil
          matcher ? matcher.ids(current_user.entries) : []
        end
      end

      def pool
        @pool ||= own_filter? ? current_user.entries.where.not(id: left_out_ids) : current_user.random_entries
      end

      # nil: as the email has it.
      def include_old
        return nil unless current_user.is_pro? && params.key?(:include_old)

        ActiveModel::Type::Boolean.new.cast(params[:include_old])
      end

      def day_json(date)
        memories = []
        if current_user.is_pro? && include_old != false
          kept = pool.pluck(:id).to_set
          memories = OnThisDay.entries(current_user, today: date).select { |entry| kept.include?(entry.id) }.sort_by(&:date).reverse
        end
        entry = memories.first || Throwback.new(current_user, today: date, pool: pool, way_back: include_old).entry
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
