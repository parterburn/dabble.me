# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/hashtags?days=365&limit=40 — hashtag counts for the Search tab's tag cloud, and
    # the vocabulary for on-device hashtag suggestions (PRO, like search).
    class HashtagsController < BaseController
      before_action :require_pro!

      def index
        days = params[:days].to_s.match?(/\A\d+\z/) ? params[:days].to_i.clamp(1, 3650) : 365
        since = OnThisDay.today_for(current_user) - days
        limit = params[:limit].to_s.match?(/\A\d+\z/) ? params[:limit].to_i.clamp(1, 200) : 40
        render json: { hashtags: HashtagCounts.new(current_user, since: since).top(limit) }
      end
    end
  end
end
