# frozen_string_literal: true

module Api
  module V1
    class SearchesController < BaseController
      before_action :require_pro!

      # GET /api/v1/search?q=  (same query syntax as the web search: OR, "exact phrase")
      def show
        term = params[:q].to_s.strip
        return render json: { entries: [], page: 1, next_page: nil, total_count: 0 } if term.blank?

        render json: paginated(Search.new(term: term, user: current_user).entries)
      end
    end
  end
end
