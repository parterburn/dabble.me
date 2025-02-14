# Handle Web Entries
class EntriesController < ApplicationController
  class InvalidDateError < StandardError; end

  include ActionView::Helpers::SanitizeHelper

  before_action :authenticate_user!
  before_action :set_entry, :require_entry_permission, only: [:show, :edit, :update, :destroy, :process_as_ai, :respond_to_ai]

  rescue_from InvalidDateError, with: :handle_invalid_date

  def index
    if params[:emotion].present?
      @entries = current_user.entries.includes(:inspiration).where("sentiment::text LIKE ?", "%#{params[:emotion]}%")
      @title = "Entries tagged with #{params[:emotion].titleize}"
    elsif params[:group] == "emotion" && params[:subgroup].present?  && params[:subgroup] =~ /^\d+$/
      @entries = current_user.entries.includes(:inspiration).where("date >= '#{params[:subgroup]}-01-01'::DATE").where.not(sentiment: []).and(current_user.entries.where.not(sentiment: ["unknown"])).sort_by(&:date)
      @title = "Entries tagged with Sentiment in #{params[:subgroup]}"
    elsif params[:group] == 'photos'
      @entries = current_user.entries.includes(:inspiration).only_images
      @title = 'Photo Entries'
    elsif params[:group] == 'ai'
      @entries = current_user.entries.includes(:inspiration).with_ai_responses
      @title = 'DabbleMeGPT Entries'
    elsif params[:subgroup].present? && params[:group].present? && params[:subgroup] =~ /^\d+$/ && params[:group] =~ /^\d+$/
      from_date = "#{params[:group]}-#{params[:subgroup]}"
      to_date = Date.parse(from_date + "-01").end_of_month
      @entries = current_user.entries.includes(:inspiration).where("date >= to_date('#{from_date}','YYYY-MM') AND date <= to_date('#{to_date}','YYYY-MM-DD')").sort_by(&:date)
      date = Date.parse(params[:subgroup] + '/' + params[:group])
      @title = "Entries from #{date.strftime('%b %Y')}"
    elsif params[:group].present?
      if params[:group] =~ /\A(19|20)\d{2}\z/
        start_date = Date.new(params[:group].to_i, 1, 1)
        end_date = Date.new(params[:group].to_i, 12, 31)
        @entries = current_user.entries.where(date: start_date..end_date)
      else
        raise InvalidDateError
      end
      @title = "Entries from #{params[:group]}"
    elsif params[:format] != "json"
      @entries = current_user.entries.includes(:inspiration)
      @title = 'All Entries'
    end

    if @entries.present?
      @entries = Kaminari.paginate_array(@entries).page(params[:page]).per(params[:per])
    elsif params[:format] != "json"
      flash[:alert] = "No entries found."
      redirect_to latest_entry_path and return
    end

    respond_to do |format|
      format.json {
        start_date = params[:start].presence || 1.years.ago.strftime("%Y-%m-%d")
        end_date = params[:end].presence || Date.today.strftime("%Y-%m-%d")
        render json: calendar_json(current_user.entries
          .where("date >= '#{start_date}'::DATE AND date < '#{end_date}'::DATE")) }
      format.html
    end
  end

  def show
    if @entry
      track_ga_event('Show')
      render 'show'
    else
      redirect_to entries_path
    end
  end

  def latest
    @title = "Latest Entry"
    @lastest_entry = current_user.entries.includes(:inspiration).sort_by(&:date).last
  end

  def random
    @entry = current_user.random_entry
    if @entry
      track_ga_event('Random')
      render 'show'
    else
      redirect_to entries_path
    end
  end

  def new
    @entry = Entry.new
  end

  def calendar
  end

  def spotify
    @title = "Songs from Entries"
  end

  def create
    if current_user.is_free?
      flash[:alert] = "<a href='#{subscribe_url}'' class='alert-link'>Subscribe to PRO</a> to write new entries.".html_safe
      redirect_to root_path and return
    end

    @existing_entry = current_user.existing_entry(params[:entry][:date].to_s)

    if @existing_entry.present? && params[:entry][:entry].present?
      @existing_entry.body = "#{@existing_entry.body}<hr>#{params[:entry][:entry]}"
      @existing_entry.inspiration_id = params[:entry][:inspiration_id] if params[:entry][:inspiration_id].present?
      if params[:entry][:image].present?
        if @existing_entry.image_url_cdn.present? || params[:entry][:image].count > 1
          image_urls = collage_from_attachments(Array(params[:entry][:image]))
          ImageCollageJob.perform_later(@existing_entry.id, urls: image_urls)
        elsif params[:entry][:image].present?
          @existing_entry.filepicker_url = "https://dabble-me.s3.amazonaws.com/uploading.png"
          best_attachment = params[:entry][:image].first
          ProcessEntryImageJob.perform_later(
            @existing_entry.id,
            attachment_data: {
              content_type: best_attachment.content_type,
              original_filename: best_attachment.original_filename,
              data: Base64.strict_encode64(File.read(best_attachment.tempfile))
            }
          )
        end
      end
      if @existing_entry.save
        flash[:notice] = "Merged with existing entry on #{@existing_entry.date.strftime("%B %-d")}."
        track_ga_event('Merged')
        redirect_to day_entry_path(year: @existing_entry.date.year, month: @existing_entry.date.month, day: @existing_entry.date.day)
      else
        render 'new'
      end
    else
      @entry = current_user.entries.create(entry_params)
      if params[:entry][:image].present? && params[:entry][:image].count > 1
        image_urls = collage_from_attachments(params[:entry][:image])
        ImageCollageJob.perform_later(@entry.id, urls: image_urls)
      elsif params[:entry][:image].present?
        @entry.filepicker_url = "https://dabble-me.s3.amazonaws.com/uploading.png"
        best_attachment = params[:entry][:image].first
        ProcessEntryImageJob.perform_later(
          @entry.id,
          attachment_data: {
            content_type: best_attachment.content_type,
            original_filename: best_attachment.original_filename,
            data: Base64.strict_encode64(File.read(best_attachment.tempfile))
          }
        )
      end

      if @entry.save
        track_ga_event('New')
        flash[:notice] = "Entry created successfully!"
        redirect_to day_entry_path(year: @entry.date.year, month: @entry.date.month, day: @entry.date.day)
      else
        render 'new'
      end
    end
  end

  def edit
    store_location
    if current_user.is_free?
      @entry.body = @entry.sanitized_body
    end
    track_ga_event('Edit')
  end

  def update
    if current_user.is_free?
      params[:entry][:entry] = @entry.body
      params[:entry][:image] = @entry.image
    end

    @existing_entry = current_user.existing_entry(params[:entry][:date].to_s)

    if @entry.present? && @existing_entry.present? && @entry != @existing_entry && params[:entry][:entry].present?
      # existing entry exists, so add to it
      @existing_entry.body = "#{@existing_entry.body}<hr>#{params[:entry][:entry]}"
      @existing_entry.inspiration_id = params[:entry][:inspiration_id] if params[:entry][:inspiration_id].present?
      if params[:entry][:image].present?
        if @existing_entry.image_url_cdn.present? || params[:entry][:image].count > 1
          image_urls = collage_from_attachments(Array(params[:entry][:image]))
          ImageCollageJob.perform_later(@existing_entry.id, urls: image_urls)
        else
          @existing_entry.filepicker_url = "https://dabble-me.s3.amazonaws.com/uploading.png"
          best_attachment = params[:entry][:image].first
          ProcessEntryImageJob.perform_later(
            @existing_entry.id,
            attachment_data: {
              content_type: best_attachment.content_type,
              original_filename: best_attachment.original_filename,
              data: Base64.strict_encode64(File.read(best_attachment.tempfile))
            }
          )
        end
      end
      if @existing_entry.save
        @entry.delete
        flash[:notice] = "Merged with existing entry on #{@existing_entry.date.strftime('%B %-d')}."
        track_ga_event('Update')
        redirect_to day_entry_path(year: @existing_entry.date.year, month: @existing_entry.date.month, day: @existing_entry.date.day) and return
      else
        render 'edit'
      end
    elsif params[:entry][:entry].blank?
      @entry.destroy
      flash[:notice] = 'Entry deleted!'
      redirect_back_or_to entries_path
    else
      update_params = if @entry.image_url_cdn.present? && entry_params[:remove_image] == "0"
        @entry.remote_image_url = @entry.image_url_cdn
        entry_params.permit(:entry, :date)
      else
        entry_params.permit(:entry, :date, :remove_image)
      end
      if @entry.update(update_params)
        if params[:entry][:image].present? && params[:entry][:image].size > 1
          image_urls = collage_from_attachments(params[:entry][:image])
          ImageCollageJob.perform_later(@entry.id, urls: image_urls)
        elsif params[:entry][:image].present?
          @entry.update(filepicker_url: "https://dabble-me.s3.amazonaws.com/uploading.png")
          best_attachment = params[:entry][:image].first
          ProcessEntryImageJob.perform_later(
            @entry.id,
            attachment_data: {
              content_type: best_attachment.content_type,
              original_filename: best_attachment.original_filename,
              data: Base64.strict_encode64(File.read(best_attachment.tempfile))
            }
          )
        end
        track_ga_event('Update')
        flash[:notice] = "Entry successfully updated!"
        redirect_to day_entry_path(year: @entry.date.year, month: @entry.date.month, day: @entry.date.day)
      else
        render 'edit'
      end
    end
  end

  def destroy
    if current_user.is_free?
      flash[:alert] = "<a href='#{subscribe_url}'' class='alert-link'>Subscribe to PRO</a> to edit entries.".html_safe
      redirect_to root_path and return
    end

    @entry.destroy
    track_ga_event('Delete')
    flash[:notice] = 'Entry deleted successfully.'
    redirect_to entries_path
  end

  def export
    filename = "dabble_export_#{Time.now.strftime('%Y-%m-%d')}.txt"
    if params[:only_images] == "true"
      @entries = current_user.entries.only_images.sort_by(&:date)
      filename = "dabble_export_image_entries_#{Time.now.strftime('%Y-%m-%d')}.txt"
    elsif params[:search].present? && search_params[:term].present?
      if search_params[:term].include?(" OR ")
        filter_names = search_params[:term].split(' OR ')
        sanitized_terms = filter_names.map { |term| ActiveRecord::Base.sanitize_sql_like(term.downcase) }
        conditions = sanitized_terms.map { |term| @entries.where("LOWER(entries.body) LIKE ?", "%#{term}%") }
        @entries = conditions.reduce(:or)
      elsif search_params[:term].include?('"')
        exact_phrase = search_params[:term].delete('"')
        sanitized_phrase = Regexp.escape(exact_phrase)
        @entries = current_user.entries.where("entries.body ~* ?", "\\m#{sanitized_phrase}\\M")
      else
        @search = Search.new(search_params)
        @entries = @search.entries
      end
      filename = "dabble_export_search_#{search_params[:term].parameterize}}_#{Time.now.strftime('%Y-%m-%d')}.txt"
    elsif params[:year].present?
      if params[:year] =~ /\A(19|20)\d{2}\z/
        start_date = Date.new(params[:year].to_i, 1, 1)
        end_date = Date.new(params[:year].to_i, 12, 31)
        @entries = current_user.entries.where(date: start_date..end_date)
        filename = "dabble_export_#{params[:year]}.txt"
      else
        raise InvalidDateError
      end
    else
      @entries = current_user.entries.sort_by(&:date)
    end
    track_ga_event('Export')
    respond_to do |format|
      format.json { send_data JSON.pretty_generate(JSON.parse(@entries.to_json(only: [:date, :body, :image]))), filename: "export_#{Time.now.strftime('%Y-%m-%d')}.json" }
      format.txt do
        response.headers['Content-Type'] = 'text/txt'
        response.headers['Content-Disposition'] = "attachment; filename=#{filename}"
        render 'text_export'
      end
    end
  end

  def review
    month = Date.today.month
    @year = params[:year] || (month > 11 ? Time.now.year : Time.now.year - 1)
    @entries = current_user.entries.where("date >= '#{@year}-01-01'::DATE AND date <= '#{@year}-12-31'::DATE").order(date: :asc)
    @total_count = @entries.count
    if @total_count.positive?
      @body_text = @entries.map { |e| ActionView::Base.full_sanitizer.sanitize(e.body) }.join(" ")
      tokeniser = WordsCounted::Tokeniser.new(@body_text)
      @words_counter = tokeniser.tokenise(exclude: Entry::WORDS_NOT_TO_COUNT)
      if @total_count > 20
        all_user_entry_count = Entry.where("date >= '#{@year}-01-01'::DATE AND date <= '#{@year}-12-31'::DATE").group(:user_id).reorder("count_all").count.values
        @pctile = (((all_user_entry_count.find_index(@total_count) + 1).to_f / all_user_entry_count.count) * 100).round
      end

      @entries_with_sentiment = @entries.select { |e| e.sentiment.present? && e.sentiment != ["unknown"] }
      if @entries_with_sentiment.count.positive?
        @sentiment_count = @entries_with_sentiment.map(&:sentiment).flatten.group_by(&:itself).transform_keys { |sentiment| "#{Entry::AiTagger::EMOTIONS[sentiment]} #{sentiment.titleize}" }.transform_values(&:count).sort_by { |_k, v| v }.reverse.to_h

        @users_sentiment_list = @entries_with_sentiment.map { |e| e.sentiment }.flatten.uniq.reject { |k, _v| k.blank? }

        months = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]
        base_data = months.map { |month| [month, 0] }.to_h

        @sentiment_by_month_data = (Entry::AiTagger::EMOTIONS.keys - ["unknown"]).map do |sentiment|
          data = @entries_with_sentiment.sort_by { |e| e.date }.select { |e| e.sentiment.include?(sentiment) }.map { |e| [e.date.strftime('%b'), 1] }.group_by(&:first).transform_values(&:count)
          { name: sentiment.titleize, data: base_data.merge(data) }
        end
      end
    elsif current_user.entries.any?
      prev_year = current_user.entries.first.date.year.to_s
      flash[:alert] = "No entries in #{@year} - sending you back to #{prev_year}"
      redirect_to review_path(prev_year)
    else
      flash[:alert] = "No entries to review :("
      redirect_to entries_path
    end
  end

  def process_as_ai
    if current_user.can_ai?
      AiEntryJob.perform_later(current_user.id, @entry.id, email: false)
      flash[:notice] = "DabbleMeGPT response is generating."
    else
      flash[:alert] = "DabbleMeGPT is not available to you."
    end
    redirect_to day_entry_path(year: @entry.date.year, month: @entry.date.month, day: @entry.date.day, ai: "generating", anchor: "generating-ai")
  end

  def respond_to_ai
    if current_user.can_ai?
      @entry.body += "<hr><strong>👤 You:</strong><br/>#{ActionController::Base.helpers.simple_format(params[:entry][:ai_response])}"
      if params[:entry][:ai_response].present? && @entry.save
        AiEntryJob.perform_later(current_user.id, @entry.id, email: false)
        flash[:notice] = "DabbleMeGPT response is generating."
      else
        flash[:alert] = "Error saving response"
      end
    else
      flash[:alert] = "DabbleMeGPT is not available to you."
    end
    redirect_to day_entry_path(year: @entry.date.year, month: @entry.date.month, day: @entry.date.day, anchor: "generating-ai")
  end

  def email_replies_test
    user = User.find(73069)
    entry_every_day = user.entries.size == (Time.now.in_time_zone(user.send_timezone).to_date - Date.parse("2025-01-25")).to_i
    render json: entry_every_day
  end

  private

  def track_ga_event(action)
    if ENV['GOOGLE_ANALYTICS_ID'].present?
      # tracker = Staccato.tracker(ENV['GOOGLE_ANALYTICS_ID'])
      # tracker.event(category: 'Web Entry', action: action, label: current_user.user_key)
    end
  end

  def entry_params
    params.require(:entry).permit(:date, :entry, :inspiration_id, :remove_image, :remote_image_url)
  end

  def set_entry
    if params[:day].present?
      date = Date.parse("#{params[:year]}-#{params[:month]}-#{params[:day]}")
      @entry = current_user.entries.includes(:inspiration).where(date: date).first
    else
      @entry = current_user.entries.includes(:inspiration).where(id: params[:id]).first
    end
  rescue
    flash[:alert] = "Entry not found."
  end

  def require_entry_permission
    return false if @entry.present? && current_user == @entry.user

    flash[:alert] = 'Not authorized'
    redirect_to entries_path
  end

  def random_inspiration
    count = Inspiration.without_imports_or_email.count
    return nil if count == 0

    Inspiration.without_imports_or_email.offset(rand(count)).first
  end

  def calendar_json(entries)
    return false unless current_user.is_pro?
    json_hash = []
    entries.each do |entry|
      if entry.image.present?
        title = "📸#{ActionController::Base.helpers.strip_tags(entry.sanitized_body&.gsub(/\n/, ''))&.truncate(40, separator: ' ')}"
      else
        title = ActionController::Base.helpers.strip_tags(entry.sanitized_body&.gsub(/\n/, ''))&.truncate(50, separator: ' ')
      end
      json_hash << {
        id: entry.id,
        title: title,
        url: day_entry_path(year: entry.date.year, month: entry.date.month, day: entry.date.day),
        start: entry.date.strftime('%Y-%m-%d'),
        allDay: 'true'
      }
    end
    json_hash.to_json
  end

  def spotify_entries
    @spotify_entries ||= current_user.entries.only_spotify
  end
  helper_method :spotify_entries

  def collage_from_attachments(attachments, existing_image_url: nil)
    allowed_types = %w[image/jpeg image/png image/gif image/heic image/heif]
    attachments.each do |att|
      unless allowed_types.include?(Marcel::MimeType.for(att))
        raise "Invalid file type"
      end
    end
    s3 = Fog::Storage.new({
      provider:              "AWS",
      aws_access_key_id:     ENV["AWS_ACCESS_KEY_ID"],
      aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
    })

    directory = s3.directories.new(key: ENV["AWS_BUCKET"])

    add_dev = "/development" unless Rails.env.production?
    folder = "uploads#{add_dev}/tmp/#{Date.today.strftime("%Y-%m-%d")}/"

    attachments.first(7).map do |att|
      file_key = "#{folder}#{SecureRandom.uuid}#{File.extname(att)}"
      file = directory.files.create(key: file_key, body: att, public: true, content_disposition: "inline", cache_control: "public, max-age=#{365.days.to_i}")
      file.public_url
    end
  end

  def search_params
    params.require(:search).permit(:term).merge(user: current_user)
  end

  def handle_invalid_date
    flash[:alert] = "Invalid date format"
    redirect_to entries_path
  end

  def sanitize_search_term(term)
    sanitize(term, tags: [])
  end
end
