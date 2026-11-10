# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/prompts: a random handful of the curated writing prompts (the Inspirations used
    # in emails and on Today). The app's Apple Intelligence picks the one that best fits the
    # writer's recent entries, so prompts are always one of these, word for word.
    class PromptsController < BaseController
      MAX = 30

      def index
        count = params[:count].to_s.match?(/\A\d+\z/) ? params[:count].to_i.clamp(1, MAX) : 20
        prompts = Inspiration.writing_prompts.where.not(body: [nil, ""]).order(Arel.sql("RANDOM()")).limit(count).pluck(:body)
        render json: { prompts: prompts.map(&:squish).uniq }
      end
    end
  end
end
