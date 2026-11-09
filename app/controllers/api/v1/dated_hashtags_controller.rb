# frozen_string_literal: true

module Api
  module V1
    # Dated hashtags (PRO), like the web settings' "Associate dates to your tags": a date for a
    # #tag (a birthday, an anniversary) so entries show how long it had been ("3 years and 4 months
    # since entry").
    #
    # GET    /api/v1/dated_hashtags       → { hashtags: [{id, tag, date}], suggestions: ["kids", ...] }
    # POST   /api/v1/dated_hashtags       { tag, date: "2020-01-31" }
    # PATCH  /api/v1/dated_hashtags/:id   { tag, date }
    # DELETE /api/v1/dated_hashtags/:id
    class DatedHashtagsController < BaseController
      before_action :require_pro!
      before_action :find_hashtag, only: %i[update destroy]

      def index
        dated = current_user.original_hashtags.order(:tag).to_a
        taken = dated.map { |hashtag| hashtag.tag.downcase }
        # The tags used most lately that don't have a date yet.
        suggestions = HashtagCounts.new(current_user, since: 2.years.ago.to_date).top(40)
                                   .map { |item| item[:tag] }
                                   .reject { |tag| taken.include?(tag.downcase) }
                                   .first(12)
        render json: { hashtags: dated.map { |hashtag| hashtag_json(hashtag) }, suggestions: suggestions }
      end

      def create
        save(current_user.original_hashtags.new, status: :created)
      end

      def update
        save(@hashtag)
      end

      def destroy
        @hashtag.destroy!
        head :no_content
      end

      private

      def find_hashtag
        @hashtag = current_user.original_hashtags.find_by(id: params[:id])
        render_error(:not_found, 'not_found', 'Hashtag not found.') unless @hashtag
      end

      def save(hashtag, status: :ok)
        hashtag.tag = params[:tag].to_s.strip.delete_prefix('#') if params.key?(:tag)
        if params.key?(:date)
          date = Date.iso8601(params[:date].to_s) rescue nil
          return render_error(:unprocessable_content, 'invalid', 'Date must be YYYY-MM-DD.') unless date

          hashtag.date = date
        end
        unless hashtag.tag.to_s.match?(/\A[A-Za-z0-9_]+\z/)
          return render_error(:unprocessable_content, 'invalid', 'A hashtag is letters, numbers and underscores.')
        end

        if hashtag.save
          render json: hashtag_json(hashtag), status: status
        else
          render_error(:unprocessable_content, 'invalid', hashtag.errors.full_messages.to_sentence)
        end
      end

      def hashtag_json(hashtag)
        { id: hashtag.id, tag: hashtag.tag, date: hashtag.date&.to_date&.iso8601 }
      end
    end
  end
end
