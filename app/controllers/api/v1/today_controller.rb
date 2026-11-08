# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/today: everything the app's Today tab shows in one request.
    class TodayController < BaseController
      def show
        today = OnThisDay.today_for(current_user)
        entry = current_user.existing_entry(today.to_s)
        memories = current_user.is_pro? ? OnThisDay.entries(current_user, today: today) : []

        render json: {
          date: today.iso8601,
          entry: entry && EntrySerializer.full(entry),
          on_this_day: memories.map { |memory| EntrySerializer.summary(memory).merge(years_ago: today.year - memory.date.year) },
          on_this_day_available: current_user.is_pro?,
          prompt: daily_prompt(today)
        }
      end

      private

      # Same writing prompt all day (changes daily), from the Inspirations used in emails.
      def daily_prompt(today)
        prompts = Inspiration.writing_prompts.order(:id)
        count = prompts.count
        return nil if count.zero?

        prompts.offset(today.yday % count).first&.body
      end
    end
  end
end
