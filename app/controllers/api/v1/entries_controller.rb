# frozen_string_literal: true

module Api
  module V1
    class EntriesController < BaseController
      before_action :require_pro!, only: %i[create update destroy on_this_day]
      before_action :set_entry, only: %i[show update destroy]

      # GET /api/v1/entries?page=&per=&year=&month=
      def index
        entries = current_user.entries
        if params[:year].present?
          year = params[:year].to_s
          month = params[:month].to_s
          return render_error(:unprocessable_content, 'invalid_date', 'Invalid year.') unless year.match?(/\A(19|20)\d{2}\z/)

          if month.present?
            return render_error(:unprocessable_content, 'invalid_date', 'Invalid month.') unless month.match?(/\A(1[0-2]|0?[1-9])\z/)

            from = Date.new(year.to_i, month.to_i, 1)
            entries = entries.where(date: from.beginning_of_day..from.end_of_month.end_of_day)
          else
            entries = entries.where(date: Date.new(year.to_i, 1, 1).beginning_of_day..Date.new(year.to_i, 12, 31).end_of_day)
          end
        end

        render json: paginated(entries)
      end

      def show
        render json: { entry: EntrySerializer.full(@entry) }
      end

      def random
        entry = current_user.random_entry
        return render_error(:not_found, 'not_found', 'No entries yet.') unless entry

        render json: { entry: EntrySerializer.full(entry) }
      end

      # Entries from this calendar day in earlier years (PRO on the web too).
      def on_this_day
        user_time = Time.current.in_time_zone(current_user.send_timezone)
        first_year = current_user.entries.minimum(:date)&.year || user_time.year
        day_ranges = (1..(user_time.year - first_year)).map { |y| (user_time - y.years).to_date.all_day }
        scope = day_ranges.map { |range| current_user.entries.where(date: range) }.reduce(:or)
        entries = scope ? scope.to_a : []
        render json: { entries: entries.map { |entry| EntrySerializer.summary(entry) } }
      end

      # POST /api/v1/entries { date: "YYYY-MM-DD", document: [...] | body: "plain text", uploaded_image_keys: [...] }
      # Appends to that day's entry if one exists, matching the web compose flow.
      def create
        body_html = document_html if params.key?(:document)
        return if performed?

        result = Mcp::EntryCreator.new(user: current_user).create(
          date_string: params[:date].presence || Mcp::Tools::Helpers.default_entry_date_iso8601(current_user),
          body_text: params[:body],
          body_html: body_html,
          merge_with_existing: true,
          uploaded_image_keys: Array(params[:uploaded_image_keys]).map(&:to_s)
        )
        return render_error(:unprocessable_content, 'invalid', 'Could not save the entry.', details: result[:errors]) unless result[:success]

        entry = current_user.entries.find(result[:entry][:id])
        render json: { entry: EntrySerializer.full(entry), merged: result[:merged] },
               status: result[:merged] ? :ok : :created
      end

      # PATCH /api/v1/entries/:id { document: [...] } — only for entries whose `document` is non-null.
      def update
        if EntryDocument.from_html(@entry.body).nil?
          return render_error(:unprocessable_content, 'not_editable',
                              'This entry has formatting the app cannot edit yet. Edit it on dabble.me instead.')
        end

        html = document_html
        return if performed?
        if Rails::HTML5::FullSanitizer.new.sanitize(html).strip.blank?
          return render_error(:unprocessable_content, 'invalid', 'Entry cannot be blank. Delete the entry instead.')
        end

        if @entry.update(body: html)
          render json: { entry: EntrySerializer.full(@entry) }
        else
          render_error(:unprocessable_content, 'invalid', 'Could not save the entry.', details: @entry.errors.full_messages)
        end
      end

      def destroy
        @entry.destroy
        head :no_content
      end

      private

      def set_entry
        @entry = current_user.entries.find(params[:id])
      end

      def document_html
        EntryDocument.to_html(params[:document])
      rescue EntryDocument::InvalidDocument => e
        render_error(:unprocessable_content, 'invalid_document', e.message)
        nil
      end
    end
  end
end
