# frozen_string_literal: true

module Api
  module V1
    # The Journal tab's Stats view (PRO). GET /api/v1/stats: everything it opens with.
    class StatsController < BaseController
      before_action :require_pro!

      def show
        render json: JournalStats.new(current_user).as_json
      end

      # GET /api/v1/stats/days?year=2024 — one calendar year, for looking back through Stats: the
      # days with an entry and the year's hashtags.
      # { year: 2024, days: ["2024-01-03", ...], top_hashtags: [{ tag:, count: }] }
      def days
        stats = JournalStats.new(current_user)
        year = params[:year].to_s.match?(/\A\d{4}\z/) ? params[:year].to_i : stats.today.year
        first = Date.new(year, 1, 1)
        render json: { year: year, days: stats.writing_days_in(year),
                       top_hashtags: HashtagCounts.new(current_user, since: first, upto: first.end_of_year).top(10) }
      end
    end
  end
end
