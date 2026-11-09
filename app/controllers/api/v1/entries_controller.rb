# frozen_string_literal: true

module Api
  module V1
    class EntriesController < BaseController
      # Free accounts can write text entries (like free email replies); photos, editing,
      # deleting and On This Day are PRO.
      # Free accounts can write and delete; editing, photos and links are PRO.
      before_action :require_pro!, only: %i[update on_this_day memory_days]
      before_action :require_pro_for_photos!, only: :create
      before_action :set_entry, only: %i[show update destroy]

      # GET /api/v1/entries?page=&per=&year=&month=&photos=1 (photos: only entries with a photo)
      def index
        entries = current_user.entries
        entries = entries.where("image IS NOT NULL AND image != ''") if params[:photos] == '1'
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

      # GET /api/v1/entries/months: every month with entries, newest first, for the
      # Journal tab's month sections and year/month scrubber.
      def months
        counts = current_user.entries.unscope(:order)
                             .group(Arel.sql("DATE_PART('year', date)"), Arel.sql("DATE_PART('month', date)"))
                             .count
        months = counts.map { |(year, month), count| { year: year.to_i, month: month.to_i, count: count } }
                       .sort_by { |m| [-m[:year], -m[:month]] }
        render json: { months: months }
      end

      # GET /api/v1/entries/days — every date with an entry (YYYY-MM-DD, newest first), for the
      # Journal's jump-to-a-day calendar. Dates only.
      def days
        dates = current_user.entries.unscope(:order).distinct.pluck(Arel.sql("DATE(date)"))
        render json: { days: dates.compact.sort.reverse.map(&:iso8601) }
      end

      # GET /api/v1/entries/memory_days?days=30 — upcoming days (from today, in the journal's
      # time zone) that have entries from earlier years, for the app's On This Day reminders.
      # Counts only, never entry text: notifications can show up on a lock screen.
      def memory_days
        days = params[:days].to_s.match?(/\A\d+\z/) ? params[:days].to_i.clamp(1, 60) : 30
        today = OnThisDay.today_for(current_user)
        month = Arel.sql("DATE_PART('month', date)")
        day = Arel.sql("DATE_PART('day', date)")
        by_month_day = current_user.entries.unscope(:order)
                                   .where('date < ?', today.beginning_of_day)
                                   .group(month, day)
                                   .pluck(month, day, Arel.sql('COUNT(*)'), Arel.sql("MIN(DATE_PART('year', date))"))
                                   .to_h { |m, d, count, first_year| [[m.to_i, d.to_i], [count, first_year.to_i]] }

        upcoming = (0...days).filter_map do |offset|
          date = today + offset
          count, first_year = by_month_day[[date.month, date.day]]
          { date: date.iso8601, count: count, first_year: first_year } if count
        end
        render json: { days: upcoming }
      end

      def random
        entry = current_user.random_entry
        return render_error(:not_found, 'not_found', 'No entries yet.') unless entry

        render json: { entry: EntrySerializer.full(entry) }
      end

      # Entries from this calendar day in earlier years (PRO on the web too).
      def on_this_day
        render json: { entries: OnThisDay.entries(current_user).map { |entry| EntrySerializer.summary(entry) } }
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

      # PATCH /api/v1/entries/:id { document: [...], remove_image: true, uploaded_image_keys: [...] }
      # Any of them. `document` only for entries whose `document` is non-null. New photos join the
      # entry's photo in a collage (like adding to a day on create), or replace it with remove_image.
      def update
        if params.key?(:document)
          if EntryDocument.from_html(@entry.body).nil?
            return render_error(:unprocessable_content, 'not_editable',
                                'This entry has formatting the app cannot edit yet. Edit it on dabble.me instead.')
          end

          html = document_html
          return if performed?
          if Rails::HTML5::FullSanitizer.new.sanitize(html).strip.blank?
            return render_error(:unprocessable_content, 'invalid', 'Entry cannot be blank. Delete the entry instead.')
          end

          @entry.body = html
        end

        photo_keys = Array(params[:uploaded_image_keys]).map { |key| key.to_s.strip }.compact_blank.uniq
        unless photo_keys.all? { |key| Mcp::PresignedImageUpload.key_allowed_for_user?(current_user, key) }
          return render_error(:unprocessable_content, 'invalid', 'A photo upload is not valid for this account.')
        end

        remove_image = ActiveModel::Type::Boolean.new.cast(params[:remove_image])
        @entry.remove_image = true if remove_image && @entry.image_stored?
        keeps_photo = @entry.image_stored? && !remove_image
        if photo_keys.size + (keeps_photo ? 1 : 0) > CollageGenerator::MAX_IMAGES
          return render_error(:unprocessable_content, 'invalid', "An entry can have up to #{CollageGenerator::MAX_IMAGES} photos.")
        end

        collage = photo_keys.size > 1 || (photo_keys.any? && keeps_photo)
        @entry.uploading_image = true if photo_keys.any?
        if @entry.save
          if collage
            ImageCollageJob.perform_later(@entry.id, urls: photo_keys.map { |key| Mcp::PresignedImageUpload.public_url(key) })
          elsif photo_keys.any?
            ProcessEntryImageJob.perform_later(@entry.id, photo_keys.first)
          end
          render json: { entry: EntrySerializer.full(@entry.reload) }
        else
          render_error(:unprocessable_content, 'invalid', 'Could not save the entry.', details: @entry.errors.full_messages)
        end
      end

      def destroy
        @entry.destroy
        head :no_content
      end

      private

      def require_pro_for_photos!
        return if current_user.is_pro? || Array(params[:uploaded_image_keys]).compact_blank.empty?

        render_error(:forbidden, 'pro_required', 'Adding photos is part of Dabble Me PRO.')
      end

      def set_entry
        @entry = current_user.entries.find(params[:id])
      end

      def document_html
        EntryDocument.to_html(params[:document], links: current_user.is_pro?)
      rescue EntryDocument::InvalidDocument => e
        render_error(:unprocessable_content, 'invalid_document', e.message)
        nil
      end
    end
  end
end
