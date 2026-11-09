# frozen_string_literal: true

module Api
  module V1
    # GET/PATCH /api/v1/email_schedule — when the "How was your day?" email arrives and which past
    # entry it includes, like the web settings page. Everyone sets the hour and time zone and whether
    # to include a past entry; choosing days beyond Sunday, words to leave out, and entries over a
    # year old are PRO (free accounts get Sunday or nothing, as User#restrict_free_frequency enforces).
    class EmailSchedulesController < BaseController
      DAYS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

      def show
        render json: schedule_json
      end

      # PATCH { days: ["Mon", ...], hour: 0-23, timezone: "Pacific Time (US & Canada)",
      #         include_past_entries: true, past_filter: "work, doctor", include_old_entries: true }
      # (any of them)
      def update
        user = current_user
        if params.key?(:days)
          days = Array(params[:days]).map(&:to_s)
          return render_error(:unprocessable_content, 'invalid', 'Unknown day.') unless (days - DAYS).empty?
          if !user.is_pro? && (days - ['Sun']).any?
            return render_error(:forbidden, 'pro_required', 'Choosing more days is part of Dabble Me PRO.')
          end

          user.frequency = DAYS & days
        end
        if params.key?(:hour)
          hour = params[:hour].to_s
          return render_error(:unprocessable_content, 'invalid', 'Hour must be 0 to 23.') unless hour.match?(/\A\d{1,2}\z/) && hour.to_i.between?(0, 23)

          user.send_time = format('%02d:00', hour.to_i)
        end
        if params.key?(:timezone)
          zone = ActiveSupport::TimeZone[params[:timezone].to_s]
          return render_error(:unprocessable_content, 'invalid', 'Unknown time zone.') unless zone

          user.send_timezone = zone.name
        end
        user.send_past_entry = boolean(:include_past_entries) if params.key?(:include_past_entries)
        if params.key?(:past_filter) || params.key?(:include_old_entries)
          return render_error(:forbidden, 'pro_required', 'This is part of Dabble Me PRO.') unless user.is_pro?

          user.past_filter = params[:past_filter].to_s.split(',').map(&:strip).reject(&:blank?).join(', ').presence if params.key?(:past_filter)
          user.way_back_past_entries = boolean(:include_old_entries) if params.key?(:include_old_entries)
        end

        if user.save
          render json: schedule_json
        else
          render_error(:unprocessable_content, 'invalid', 'Could not save your email schedule.', details: user.errors.full_messages)
        end
      end

      private

      def boolean(key)
        ActiveModel::Type::Boolean.new.cast(params[key]) ? true : false
      end

      def schedule_json
        user = current_user.reload
        {
          days: DAYS & Array(user.frequency),
          hour: user.send_time.hour,
          timezone: user.send_timezone,
          can_choose_days: user.is_pro?,
          include_past_entries: user.send_past_entry != false,
          past_filter: user.past_filter.to_s,
          # How many entries the words leave out (the web links these to a search).
          filtered_count: user.past_filter.present? ? Array(user.past_filter_entry_ids).size : 0,
          include_old_entries: user.way_back_past_entries != false,
          # The web only offers "over a year old" once there are entries that old.
          has_old_entries: user.entries.where(date: ...1.year.ago).exists?,
          time_zones: ActiveSupport::TimeZone.all.map do |zone|
            { name: zone.name, iana: zone.tzinfo.name, offset: zone.formatted_offset }
          end
        }
      end
    end
  end
end
