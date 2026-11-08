# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/hashtags?days=365 — hashtag counts for the Search tab's tag cloud (PRO, like search).
    class HashtagsController < BaseController
      before_action :require_pro!

      def index
        days = params[:days].to_s.match?(/\A\d+\z/) ? params[:days].to_i.clamp(1, 3650) : 365
        since = OnThisDay.today_for(current_user) - days
        render json: { hashtags: HashtagCounts.new(current_user, since: since).top(40) }
      end
    end
  end
end
