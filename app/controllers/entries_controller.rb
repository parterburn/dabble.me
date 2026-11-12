# Handle Web Entries
class EntriesController < ApplicationController
  class InvalidDateError < StandardError; end

  include ActionView::Helpers::SanitizeHelper

  before_action :authenticate_user!
  before_action :set_entry, :require_entry_permission, only: [:show, :edit, :update, :destroy, :reflection, :dismiss_image_error]

  rate_limit to: 10, within: 10.minutes, only: :reflection, with: -> { render json: { error: "Too many reflections. Try again in a few minutes." }, status: :too_many_requests }

  rescue_from InvalidDateError, with: :handle_invalid_date

  # Photos on a page of the photo grid: full rows at 3, 4 and 6 across.
  PHOTOS_PER_PAGE = 60

  def index
    @entries = current_user.entries.includes(:inspiration)

    if params[:group] == 'photos'
      @entries = @entries.only_images
      @title = 'Photos'
    elsif params[:subgroup].present? && params[:group].present? && params[:subgroup].to_s.match?(/\A\d+\z/) && params[:group].to_s.match?(/\A\d+\z/)
      begin
        from_date = Date.new(params[:group].to_i, params[:subgroup].to_i, 1)
        to_date = from_date.end_of_month
        @entries = @entries.where(date: from_date..to_date).reorder(date: :asc)
        @title = "Entries from #{from_date.strftime('%b %Y')}"
      rescue ArgumentError
        raise InvalidDateError
      end
    elsif params[:group].present?
      if params[:group].to_s.match?(/\A(19|20)\d{2}\z/)
        start_date = Date.new(params[:group].to_i, 1, 1)
        end_date = Date.new(params[:group].to_i, 12, 31)
        @entries = @entries.where(date: start_date..end_date)
      else
        raise InvalidDateError
      end
      @title = "Entries from #{params[:group]}"
    else
      @title = 'All Entries'
    end

    photo_grid = params[:group] == 'photos' && !request.format.json?
    if photo_grid
      # The grid shows only photos, so skip the entry text (and decrypting it).
      # uploading_image_at is needed by Entry#uploading_image?.
      @entries = @entries.unscope(:includes).select(:id, :user_id, :date, :image, :uploading_image_at)
                         .page(params[:page]).per(PHOTOS_PER_PAGE)
    else
      @entries = @entries.page(params[:page]).per(index_per_page)
    end

    if @entries.empty? && params[:format] != "json"
      flash[:alert] = "No entries found." if params[:group].present? || params[:subgroup].present?
      redirect_to today_path and return
    end

    set_hashtags
    set_sidebar_stats

    respond_to do |format|
      format.json {
        start_date = parse_iso_date(params[:start]) || (@user_today - 1.year)
        end_date = parse_iso_date(params[:end]) || @user_today
        render json: calendar_json(current_user.entries
          .where("date >= ? AND date < ?", start_date, end_date)) }
      format.html { render 'photos' if photo_grid }
    end
  end

  def show
    if @entry
      set_hashtags
      set_sidebar_stats
      render 'show'
    else
      redirect_to entries_path
    end
  end

  # The home page: today's entry (or a nudge to write it), the year so far,
  # and what was written on this day in earlier years.
  def today
    @title = "Today — Dabble me."
    @has_entries = current_user.entries.exists?
    @today_entry = current_user.entries.includes(:inspiration).where(date: @user_today.all_day).first
    set_hashtags
    set_sidebar_stats
    return unless current_user.is_pro?

    set_years_ago
    set_rewind_entry if @years_ago_entries.empty?
  end

  # With nothing written on this day in an earlier year, one past entry picked
  # the way the reminder emails pick theirs. The pick is kept for the day, so
  # it is worked out once and the page shows the same entry on every visit.
  def set_rewind_entry
    key = ["rewind_entry", current_user.id, current_user.updated_at.to_i, @user_today.to_date.iso8601]
    id = Rails.cache.read(key)
    entry = current_user.entries.find_by(id: id) if id
    unless entry
      entry = current_user.random_entry(@user_today.to_date)
      Rails.cache.write(key, entry.id, expires_in: 1.day) if entry
    end
    @rewind_entry = entry unless entry.nil? || entry == @today_entry
  end

  # Every entry written on this month and day in an earlier year, as
  # [years back, entry] pairs, most recent year first.
  def set_years_ago
    on_this_day = current_user.entries.includes(:inspiration)
                              .where("extract(month from date) = ? AND extract(day from date) = ?", @user_today.month, @user_today.day)
                              .where("date < ?", @user_today.beginning_of_year)
    @years_ago_entries = on_this_day.map { |entry| [@user_today.year - entry.date.year, entry] }.sort_by { |years_back, entry| [years_back, entry.id] }
  end

  def random
    @entry = current_user.random_entry
    if @entry
      set_hashtags
      set_sidebar_stats
      render 'show'
    else
      redirect_to entries_path
    end
  end

  def new
    @entry = Entry.new
  end

  def calendar
    @calendar_date = parse_calendar_date(params[:day]) || @user_today
    min_entry_year = current_user.entries.minimum(:date)&.year
    max_entry_year = current_user.entries.maximum(:date)&.year
    start_year = min_entry_year || @calendar_date.year
    end_year = [max_entry_year, @calendar_date.year, @user_today.year].compact.max
    @calendar_years = (start_year..end_year).to_a.reverse
  end

  def spotify
    @title = "Songs"
    set_hashtags
    set_sidebar_stats
  end

  def create
    if current_user.is_free?
      flash[:alert] = "<a href='#{subscribe_path}' class='alert-link'>Subscribe to PRO</a> to write new entries.".html_safe
      redirect_to root_path and return
    end

    @existing_entry = current_user.existing_entry(params[:entry][:date].to_s)

    if @existing_entry.present? && params[:entry][:entry].present?
      @existing_entry.body = "#{@existing_entry.body}<hr>#{params[:entry][:entry]}"
      @existing_entry.inspiration_id = params[:entry][:inspiration_id] if params[:entry][:inspiration_id].present?
      if params[:entry][:image].present?
        @existing_entry.uploading_image = true
        if @existing_entry.image_url_cdn.present? || params[:entry][:image].count > 1
          image_urls = collage_from_attachments(Array(params[:entry][:image]))
          ImageCollageJob.perform_later(@existing_entry.id, urls: image_urls)
        elsif params[:entry][:image].present?
          best_attachment = params[:entry][:image].first
          if best_attachment.content_type.in?(Entry::ALLOWED_IMAGE_TYPES) && best_attachment.original_filename&.downcase&.ends_with?(*%w[.heic .heif .jpg .jpeg .gif .png .webp])
            process_single_image(@existing_entry, best_attachment)
          else
            @existing_entry.uploading_image = false
          end
        end
      end
      if @existing_entry.save
        flash[:notice] = "Merged with existing entry on #{@existing_entry.date.strftime("%B %-d")}."
        redirect_to day_entry_path(year: @existing_entry.date.year, month: @existing_entry.date.month, day: @existing_entry.date.day)
      else
        render 'new'
      end
    else
      @entry = current_user.entries.create(entry_params)
      if params[:entry][:image].present? && params[:entry][:image].count > 1
        @entry.uploading_image = true
        image_urls = collage_from_attachments(params[:entry][:image])
        ImageCollageJob.perform_later(@entry.id, urls: image_urls)
      elsif params[:entry][:image].present?
        @entry.uploading_image = true
        best_attachment = params[:entry][:image].first
        if best_attachment.content_type.in?(Entry::ALLOWED_IMAGE_TYPES) && best_attachment.original_filename&.downcase&.ends_with?(*%w[.heic .heif .jpg .jpeg .gif .png .webp])
          process_single_image(@entry, best_attachment)
        else
          @entry.uploading_image = false
        end
      end

      if @entry.save
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
        @existing_entry.uploading_image = true
        if @existing_entry.image_url_cdn.present? || params[:entry][:image].count > 1
          image_urls = collage_from_attachments(Array(params[:entry][:image]))
          ImageCollageJob.perform_later(@existing_entry.id, urls: image_urls)
        else
          best_attachment = params[:entry][:image].first
          if best_attachment.content_type.in?(Entry::ALLOWED_IMAGE_TYPES) && best_attachment.original_filename&.downcase&.ends_with?(*%w[.heic .heif .jpg .jpeg .gif .png .webp])
            process_single_image(@existing_entry, best_attachment)
          else
            @existing_entry.uploading_image = false
          end
        end
      end
      if @existing_entry.save
        @entry.delete
        flash[:notice] = "Merged with existing entry on #{@existing_entry.date.strftime('%B %-d')}."
        redirect_to day_entry_path(year: @existing_entry.date.year, month: @existing_entry.date.month, day: @existing_entry.date.day) and return
      else
        render 'edit'
      end
    elsif params[:entry][:entry].blank?
      @entry.destroy
      flash[:notice] = 'Entry deleted!'
      redirect_to url_from(session.delete(:return_to)) || entries_path
    else
      # Do not re-download / re-assign the existing image on every edit. That
      # old remote_image_url workaround wiped photos when the CDN fetch failed
      # (CarrierWave validate_download is false). Date changes relocate the
      # stored object via Entry#relocate_image_on_date_change instead.
      update_params = entry_params.permit(:entry, :date, :remove_image)
      if @entry.update(update_params)
        if params[:entry][:image].present? && params[:entry][:image].size > 1
          @entry.update(uploading_image: true)
          image_urls = collage_from_attachments(params[:entry][:image])
          ImageCollageJob.perform_later(@entry.id, urls: image_urls)
        elsif params[:entry][:image].present?
          @entry.update(uploading_image: true)
          best_attachment = params[:entry][:image].first
          if best_attachment.content_type.in?(Entry::ALLOWED_IMAGE_TYPES) && best_attachment.original_filename&.downcase&.ends_with?(*%w[.heic .heif .jpg .jpeg .gif .png .webp])
            process_single_image(@entry, best_attachment)
          else
            @entry.update(uploading_image: false)
          end
        end
        flash[:notice] = "Entry successfully updated!"
        redirect_to day_entry_path(year: @entry.date.year, month: @entry.date.month, day: @entry.date.day)
      else
        render 'edit'
      end
    end
  end

  # Free accounts can delete their entries too (editing is PRO).
  def destroy
    @entry.destroy
    flash[:notice] = 'Entry deleted successfully.'
    redirect_to entries_path
  end

  # .md streams the journal as Markdown right away. Anything else is a ZIP
  # built in the background (ExportEntriesJob): the journal as a web page and
  # as Markdown, plus photos. Asking for the same ZIP again inside
  # Export::LIMIT_PERIOD downloads the last one.
  def export
    search_term = params[:search].present? ? search_params[:term].presence : nil
    year = params[:year].presence
    raise InvalidDateError if year && year !~ /\A(19|20)\d{2}\z/

    if request.format.md?
      stream_markdown_export(search_term, year)
      return
    end

    scope = Export.scope_for(year: year, search_term: search_term)
    back = edit_user_registration_path(anchor: "export")
    recent = current_user.exports.within_limit.where(scope: scope).order(:created_at).last
    if recent&.preparing?
      redirect_back fallback_location: back, notice: "Your export is already being prepared. We'll email you a link when it's ready."
    elsif recent&.downloadable?
      redirect_to download_export_path(recent)
    elsif current_user.exports.where(created_at: 1.hour.ago..).count >= Export::HOURLY_LIMIT
      redirect_back fallback_location: back, alert: "You've requested a lot of exports in the last hour. Please try again later."
    else
      export = current_user.exports.create!(scope: scope)
      ExportEntriesJob.perform_later(export.id, { search_term: search_term, year: year }.compact)
      redirect_back fallback_location: back, notice: "Your export is being prepared. We'll email you a link to download it. The link works for 7 days."
    end
  end

  def review
    raw_year = params[:year].presence || (@user_today.month > 11 ? @user_today.year : @user_today.year - 1)
    raise InvalidDateError unless raw_year.to_s =~ /\A(19|20)\d{2}\z/

    @year = raw_year.to_i
    year_range = Date.new(@year, 1, 1)..Date.new(@year, 12, 31)
    @entries = current_user.entries.where(date: year_range).order(date: :asc)
    @total_count = @entries.count
    @years_with_entries = current_user.entries.pluck(:date).compact.map(&:year).uniq.sort
    entry_days = @entries.pluck(:date).compact.map(&:to_date).uniq.sort
    @longest_streak = entry_days.slice_when { |day, next_day| next_day != day + 1 }.map(&:size).max.to_i
    if @total_count.positive?
      @body_text = @entries.map { |e| ActionView::Base.full_sanitizer.sanitize(e.body) }.join(" ")
      tokeniser = WordsCounted::Tokeniser.new(@body_text)
      @words_counter = tokeniser.tokenise(exclude: Entry::WORDS_NOT_TO_COUNT)
      if @total_count > 20
        all_user_entry_count = Entry.where(date: year_range).group(:user_id).reorder("count_all").count.values
        @pctile = (((all_user_entry_count.find_index(@total_count) + 1).to_f / all_user_entry_count.count) * 100).round
      end
    elsif current_user.entries.any?
      prev_year = current_user.entries.first.date.year.to_s
      flash[:alert] = "No entries in #{@year} - sending you back to #{prev_year}"
      redirect_to rewind_path(prev_year)
    else
      flash[:alert] = "No entries to review :("
      redirect_to entries_path
    end
  end

  # A one-off AI reflection on this entry, shown in a modal. Not saved.
  def reflection
    return render(json: { error: "AI reflections aren't available on your account." }, status: :forbidden) unless current_user.can_ai?
    return render(json: { error: "AI reflections are turned off right now." }, status: :service_unavailable) unless Entry::AiAssistant.configured?
    return render(json: { error: "This entry has no text to reflect on." }, status: :unprocessable_content) if @entry.text_body.blank?

    html = @entry.ai_reflection
    if html.present?
      render json: { html: helpers.sanitize(html, tags: %w[p strong em b i ul ol li br]) }
    else
      render json: { error: "The AI couldn't come up with anything for this one. Try again." }, status: :bad_gateway
    end
  rescue RubyLLM::Error, Faraday::Error => e
    Sentry.capture_exception(e, level: :info)
    render json: { error: "The AI service didn't respond. Try again in a minute." }, status: :bad_gateway
  end

  # Clear the image_error banner that ImageCollageJob / ProcessEntryImageJob
  # writes to `entries.image_error` when async image processing fails. Called
  # via the × on the alert in `_entry.html.erb`.
  def dismiss_image_error
    @entry.update(image_error: nil)
    redirect_back fallback_location: day_entry_path(year: @entry.date.year, month: @entry.date.month, day: @entry.date.day)
  end

  private

  def entry_params
    # NOTE: `:image` is intentionally NOT permitted here. Entry#image is a
    # singular CarrierWave mount, but the form posts `entry[image][]` as an
    # array (the `multiple: true` file field supports collages of up to N
    # photos). Permitting `image: []` would cause mass-assignment to call
    # `entry.image = <array>`, which CarrierWave then tries to cache and
    # blows up in `workfile_path` with "no implicit conversion of nil into
    # String" on the array entries that have no `original_filename`.
    # The create/update actions read `params[:entry][:image]` directly and
    # route the files to `collage_from_attachments` or `process_single_image`.
    # The resulting "Unpermitted parameter: :image" log line is expected.
    params.require(:entry).permit(:date, :entry, :inspiration_id, :remove_image, :remote_image_url)
  end

  def set_entry
    if params[:day].present?
      year, month, day = [params[:year], params[:month], params[:day]].map(&:to_s)
      raise ArgumentError unless [year, month, day].all? { |part| part.match?(/\A\d{1,4}\z/) }

      date = Date.new(year.to_i, month.to_i, day.to_i)
      # entries.date is datetime; match the whole calendar day (see User#existing_entry)
      @entry = current_user.entries.includes(:inspiration).where(date: date.all_day).first
    else
      @entry = current_user.entries.includes(:inspiration).where(id: params[:id]).first
    end
  rescue ArgumentError, TypeError
    @entry = nil
    flash[:alert] = 'Entry not found.'
  end

  def require_entry_permission
    return if @entry.present? && current_user == @entry.user

    flash[:alert] = @entry.blank? ? 'Entry not found.' : 'Not authorized'
    redirect_to entries_path
  end

  def index_per_page
    raw = params[:per]
    per = if raw.is_a?(String) || raw.is_a?(Numeric)
      raw.to_s.match?(/\A\d+\z/) ? raw.to_i : nil
    end
    return Kaminari.config.default_per_page if per.nil? || per <= 0

    per.clamp(1, 50)
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
      if entry.image_stored?
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
    attachments = attachments.select do |att|
      Entry::ALLOWED_IMAGE_TYPES.include?(Marcel::MimeType.for(att))
    end

    add_dev = "/development" unless Rails.env.production?
    folder = "uploads#{add_dev}/tmp/#{Date.today.strftime("%Y-%m-%d")}/"

    attachments.first(CollageGenerator::MAX_IMAGES).map do |att|
      # Convert HEIC to JPEG if needed
      filename = att.original_filename
      if File.extname(att.original_filename)&.downcase == ".heic" || File.extname(att.original_filename)&.downcase == ".heif" || att.content_type&.include?("heic") || att.content_type&.include?("heif")
        begin
          tempfile = ImageConverter.new(tempfile: att, width: 1200).call
          jpeg_file = ActionDispatch::Http::UploadedFile.new(
            {
              filename: "#{filename.split('.').first}.jpg",
              tempfile: tempfile,
              type: 'image/jpg',
              head: "Content-Disposition: form-data; name=\"property[images][]\"; filename=\"#{filename.split('.').first}.jpg\"\r\nContent-Type: image/jpg\r\n"
            }
          )
          att = jpeg_file
        rescue => e
          Rails.logger.error "Failed to convert HEIC to JPEG: #{e.message}"
        end
      end

      file_key = "#{folder}#{SecureRandom.uuid}#{File.extname(filename)}"
      file = UploadToS3.new(file_key: file_key, body: att).call
      file.public_url
    end
  end

  def search_params
    params.require(:search).permit(:term).merge(user: current_user)
  end

  def set_hashtags
    @hashtags = current_user.original_hashtags.to_a.index_by { |h| h.tag&.downcase }
  end

  def set_sidebar_stats
    @all_entries = current_user.entries
    all_entries_size = @all_entries.count

    # Consolidate main counts into a single query for speed
    stats = Rails.cache.fetch("user_#{current_user.id}_main_stats_#{all_entries_size}", expires_in: 1.hour) do
      @all_entries.unscope(:order).select(
        "count(*) as total",
        "count(*) FILTER (WHERE image IS NOT NULL AND image != '') as images",
        "count(*) FILTER (WHERE songs::text NOT IN ('[]', '{}')) as spotify"
      ).take.attributes.slice("total", "images", "spotify")
    end

    @total_entries_count = stats["total"].to_i
    @only_images_count = stats["images"].to_i
    @only_spotify_count = stats["spotify"].to_i

    @entries_by_year = Rails.cache.fetch("user_#{current_user.id}_entries_by_year_#{all_entries_size}", expires_in: 1.hour) do
      @all_entries.unscope(:order).group("DATE_PART('year', date)").count.transform_keys { |k| k.to_i.to_s }.sort.reverse.to_h
    end

    if params[:group].present? && params[:group] =~ /\A(19|20)\d{2}\z/
      @entries_by_month = Rails.cache.fetch("user_#{current_user.id}_entries_by_month_#{params[:group]}_#{all_entries_size}", expires_in: 1.hour) do
        @all_entries.unscope(:order).where("DATE_PART('year', date) = ?", params[:group]).group("DATE_PART('month', date)").count.transform_keys { |k| k.to_i }.to_h
      end
    end
  end

  def handle_invalid_date
    flash[:alert] = "Invalid date format"
    redirect_to entries_path
  end

  # Parse a user-supplied ISO date (YYYY-MM-DD) for use in SQL bind params.
  # Returns nil for blank/invalid input so callers can fall back to a default.
  def parse_iso_date(value)
    return nil if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Calendar deep links use YYYY-MM or YYYY-MM-DD (from the entries sidebar).
  def parse_calendar_date(value)
    return if value.blank?

    str = value.to_s
    if str.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(str)
    elsif str.match?(/\A\d{4}-\d{2}\z/)
      Date.strptime(str, '%Y-%m')
    end
  rescue Date::Error, ArgumentError, TypeError
    nil
  end

  def sanitize_search_term(term)
    sanitize(term, tags: [])
  end

  def process_single_image(entry, attachment)
    file_key = "uploads/tmp/#{entry.user.id}/#{Date.today.strftime("%Y-%m-%d")}/#{SecureRandom.uuid}#{File.extname(attachment.original_filename)}"
    file = UploadToS3.new(file_key: file_key, body: attachment.read).call

    ProcessEntryImageJob.perform_later(
      entry.id,
      file.key
    )
  end

  def stream_markdown_export(search_term, year)
    entries = if search_term
                Search.new(term: search_term, user: current_user).entries
              elsif year
                current_user.entries.where(date: Time.utc(year.to_i).all_year)
              else
                current_user.entries
              end
    name = ["dabble-me", year, ("search" if search_term), Time.current.strftime("%Y-%m-%d")].compact.join("-")

    headers["Content-Type"] = "text/markdown; charset=utf-8"
    headers["Content-Disposition"] = %(attachment; filename="#{name}.md")
    headers["Cache-Control"] = "no-store"
    # Rack::ETag would read the whole body to hash it; this stops it.
    headers["Last-Modified"] = Time.current.httpdate
    self.response_body = ExportMarkdown.stream(entries)
  end
end
