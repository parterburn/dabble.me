# frozen_string_literal: true

module Api
  module V1
    # GET/PATCH /api/v1/email_schedule — when the "How was your day?" email arrives, like the web
    # settings page. Everyone sets the hour and time zone; choosing days beyond Sunday is PRO (free
    # accounts get Sunday or nothing, as User#restrict_free_frequency enforces).
    class EmailSchedulesController < BaseController
      DAYS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

      def show
        render json: schedule_json
      end

      # PATCH { days: ["Mon", ...], hour: 0-23, timezone: "Pacific Time (US & Canada)" } (any of them)
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

        if user.save
          render json: schedule_json
        else
          render_error(:unprocessable_content, 'invalid', 'Could not save your email schedule.', details: user.errors.full_messages)
        end
      end

      private

      def schedule_json
        user = current_user.reload
        {
          days: DAYS & Array(user.frequency),
          hour: user.send_time.hour,
          timezone: user.send_timezone,
          can_choose_days: user.is_pro?,
          time_zones: ActiveSupport::TimeZone.all.map do |zone|
            { name: zone.name, iana: zone.tzinfo.name, offset: zone.formatted_offset }
          end
        }
      end
    end
  end
end
