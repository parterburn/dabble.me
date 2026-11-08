# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/stats — the Journal tab's Stats view (like the web's yearly review, free).
    class StatsController < BaseController
      def show
        render json: JournalStats.new(current_user).as_json
      end
    end
  end
end
