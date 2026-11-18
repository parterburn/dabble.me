class ImageCollageJob < ActiveJob::Base
  class MailgunStoredEventNotFound < StandardError
    attr_reader :message_id, :lookup_log

    def initialize(message_id, lookup_log: [])
      @message_id = message_id
      @lookup_log = lookup_log
      super("No last message found for message ID #{message_id}")
    end
  end

  queue_as :default

  # Mailgun often needs a minute before inbound `stored` events are searchable.
  MAILGUN_INDEX_DELAY = 60.seconds
  MAILGUN_LOOKUP_JOB_ATTEMPTS = 10
  MAILGUN_LOOKUP_ROUNDS = 3

  # Sidekiq will retry unhandled exceptions by default. We make timeouts explicit here
  # so we can control retry timing and attempts for transient network issues.
  retry_on Net::ReadTimeout,
           Faraday::TimeoutError,
           wait: :polynomially_longer,
           attempts: 6

  retry_on MailgunStoredEventNotFound,
           wait: :polynomially_longer,
           attempts: MAILGUN_LOOKUP_JOB_ATTEMPTS do |job, error|
    record_mailgun_lookup_failure(job, error)
  end

  # recipient_key is the posting address EmailProcessor accepted the email on.
  # Passing it keeps a queued collage working if the user resets their
  # address before the job runs.
  def self.perform_later_for_mailgun(entry_id, message_id:, recipient_key: nil)
    args = { message_id: message_id }
    args[:recipient_key] = recipient_key if recipient_key.present?
    set(wait: MAILGUN_INDEX_DELAY).perform_later(entry_id, **args)
  end

  def self.record_mailgun_lookup_failure(job, error)
    entry_id = job.arguments.first
    entry = Entry.find_by(id: entry_id)
    return unless entry.present?

    user = entry.user
    Sentry.set_user(id: user.id, email: user.email)
    Sentry.capture_message(
      'Mailgun events lookup failed for collage attachments',
      level: :warning,
      extra: {
        entry_id: entry_id,
        entry_user_id: user.id,
        message_id: error.message_id,
        smtp_domain: ENV['SMTP_DOMAIN'],
        lookup_attempts: error.lookup_log,
        job_executions: job.executions
      }
    )
    record_image_failure(
      entry,
      user,
      [error.message],
      entry_id: entry_id,
      mailgun_lookup_attempts: error.lookup_log,
      message_id: error.message_id
    )
  end

  def self.record_image_failure(entry, user, error_messages, sentry_extra = {})
    Sentry.set_user(id: user.id, email: user.email)
    Sentry.capture_message(
      'Error updating collage image',
      level: :info,
      extra: sentry_extra.merge(entry_id: entry.id, error_messages: error_messages)
    )
    entry.update(image_error: error_messages.to_sentence.presence, uploading_image: false)
    cache_key = "image_collage_error_email_sent:#{entry.id}"
    unless Rails.cache.read(cache_key)
      EntryMailer.image_error(user, entry, 'collage', error_messages).deliver_later
      Rails.cache.write(cache_key, true, expires_in: 1.hour)
    end
  end

  def perform(entry_id, urls: nil, message_id: nil, recipient_key: nil)
    entry = Entry.where(id: entry_id).first
    @error = nil
    return nil unless entry.present?

    @message_id = message_id
    @recipient_key = recipient_key
    @user = entry.user

    @existing_url = entry.image.present? ? entry.image_url_cdn(cloudflare: false) : nil
    entry.update(uploading_image: true)

    collage_url = if @message_id.present?
      collage_from_mailgun_attachments
    else
      collage_from_urls(urls + [@existing_url])
    end

    # Fetch the finished collage ourselves so CarrierWave never downloads a URL.
    tempfile = nil
    5.times do |attempt|
      tempfile&.close
      tempfile&.unlink
      tempfile = fetch_collage_image(collage_url)
      if tempfile
        entry.image = tempfile
        unless entry.save
          @error = entry.errors.full_messages.to_sentence
        end
        entry.reload
        break if entry.image.present?
      end
      sleep 5 unless attempt == 4
    end
    tempfile&.close
    tempfile&.unlink

    entry.reload
    if entry.image.blank?
      error_messages = if entry.errors.any?
        entry.errors.full_messages
      elsif @error.present?
        [@error]
      else
        ['The images could not be generated or saved after several attempts. Please try uploading again via the web interface.']
      end
      sentry_extra = { url: sanitize_url(collage_url) }
      sentry_extra[:mailgun_lookup_attempts] = @mailgun_event_lookup_log if @mailgun_event_lookup_log.present?
      sentry_extra[:message_id] = @message_id if @message_id.present?
      self.class.record_image_failure(entry, @user, error_messages, sentry_extra)
    else
      # Success — clear any leftover banner from a prior failed attempt so the
      # user isn't shown a stale error over their new collage.
      entry.update(image_error: nil) if entry.image_error.present?
    end
    entry.update(uploading_image: false) if entry.uploading_image?
  end

  # Download the collage URL into a Tempfile. The URL is one this app stored
  # (or a public image already checked). SafeRemoteFetch pins the connection
  # to the resolved address and refuses a redirect onto a private host.
  # Returns a Tempfile on success (caller must close/unlink after use), nil on failure.
  def fetch_collage_image(url)
    return nil if url.blank?

    fetched = SafeRemoteFetch.fetch(url, open_timeout: 15, read_timeout: 45)
    return nil unless fetched.ok?

    tempfile = Tempfile.new(['collage', '.jpg'])
    tempfile.binmode
    tempfile.write(fetched.body)
    tempfile.rewind
    tempfile
  rescue URI::InvalidURIError, StandardError => e
    Sentry.capture_exception(e, extra: { url: sanitize_url(url) })
    nil
  end

  # The stored message must belong to this user. Besides the account email,
  # accept the posting address the email was accepted on (recipient_key) and
  # the current one, so a reset between ingestion and this job doesn't drop it.
  def message_from_user?(message)
    recipients = message["recipients"].to_s
    keys = [@recipient_key, @user.user_key].compact_blank
    keys.any? { |key| recipients.include?(key) } || message["from"].to_s.include?(@user.email)
  end

  def collage_from_mailgun_attachments
    @error = "No message ID found" unless @message_id.present?
    return unless @message_id.present?

    last_message, @mailgun_event_lookup_log = fetch_mailgun_stored_event
    unless last_message.present?
      raise MailgunStoredEventNotFound.new(@message_id, lookup_log: @mailgun_event_lookup_log)
    end

    message = fetch_stored_mailgun_message(last_message.dig("storage", "url"))
    @error = "No message found" unless message.present?
    @error = "Message not from user" unless message.present? && message_from_user?(message)
    return unless message.present? && message_from_user?(message)

    # The same per-user skips EmailProcessor applied when it counted these.
    ignored_images = IgnoredEmailImage.matcher_for(@user)
    owned_urls = message["attachments"].filter_map do |att|
      next unless mailgun_image_attachment?(att)
      next if ignored_images.ignore?(name: att["name"]) { nil }

      downloaded = MailgunStorageClient.get(att["url"])
      next unless downloaded&.ok?
      next if ignored_images.ignore?(name: att["name"]) { ImageFingerprint.from_bytes(downloaded.body) }

      own_url_for_mailgun_attachment(att, downloaded.body)
    end

    @error = "No attachments found" unless owned_urls.any?
    return nil unless owned_urls.any?

    collage_from_urls(owned_urls + [@existing_url])
  end

  def fetch_stored_mailgun_message(storage_url)
    return nil if storage_url.blank?

    5.times do |attempt|
      downloaded = MailgunStorageClient.get(storage_url)
      if downloaded&.ok?
        message = JSON.parse(downloaded.body)
        return message if message.is_a?(Hash)
      end
      sleep(10 * (2**attempt)) if attempt < 4
    rescue JSON::ParserError
      sleep(10 * (2**attempt)) if attempt < 4
    end
    nil
  end

  def mailgun_image_attachment?(att)
    return false unless att["size"].to_i > 20_000

    type = att["content-type"].to_s.downcase.split(";").first.to_s.strip
    name = att["name"].to_s.downcase
    return true if Entry::ALLOWED_IMAGE_TYPES.include?(type)

    type == "application/octet-stream" && name.match?(/\.(png|jpe?g|gif|webp|heic|heif)\z/)
  end

  # Publish bytes onto our bucket. HEIC is converted first. A body that is
  # not an image is dropped so it is never stored on the public bucket.
  def own_url_for_mailgun_attachment(att, body)
    name = att["name"].to_s
    tempfile = nil
    if heic_attachment?(att, name)
      ext = name.downcase.end_with?(".heif") ? ".heif" : ".heic"
      tempfile = Tempfile.new(["attachment", ext])
      tempfile.binmode
      tempfile.write(body)
      tempfile.rewind
      ImageConverter.new(tempfile: tempfile, width: 1200, user: @user).tmp_s3_url
    else
      return nil unless FastImage.type(StringIO.new(body)).in?([:jpeg, :png, :gif, :webp])

      publish_bytes(body, name)
    end
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  def heic_attachment?(att, name)
    type = att["content-type"].to_s.downcase
    type.include?("heic") || type.include?("heif") || name.downcase.end_with?(".heic", ".heif")
  end

  def publish_bytes(body, filename)
    ext = File.extname(filename.to_s)
    ext = ".jpg" if ext.blank?
    add_dev = "/development" unless Rails.env.production?
    file_key = "uploads#{add_dev}/tmp/#{@user.id}/mailgun/#{Date.today.strftime('%Y-%m-%d')}/#{SecureRandom.uuid}#{ext}"
    UploadToS3.new(file_key: file_key, body: body).call.public_url
  end

  def collage_from_urls(urls)
    return nil unless urls.present?

    urls.reject! { |url| url.is_a?(String) && url&.include?("googleusercontent.com/mail-sig/") }

    urls = urls.map do |url|
      next if url.blank?

      if heic_like_url?(url)
        begin
          fetched = SafeRemoteFetch.fetch(url, open_timeout: 120, read_timeout: 120)
          next unless fetched.ok?

          ext = heic_temp_extension(url)
          tempfile = Tempfile.new(['attachment', ext])
          tempfile.binmode
          tempfile.write(fetched.body)
          tempfile.rewind
          result = ImageConverter.new(tempfile: tempfile, width: 1200, user: @user).tmp_s3_url
          tempfile.close
          tempfile.unlink
          result
        rescue => e
          Sentry.capture_exception(e)
          nil
        end
      else
        url
      end
    end.compact_blank

    if urls.size == 1 && urls.first.starts_with?("http")
      urls.first
    elsif urls.any?
      CollageGenerator.new(urls: urls, user: @user).tmp_s3_url
    end
  end

  private

  # Inbound multi-attachment emails are indexed as `stored` events; `accepted` is
  # primarily outbound. Try both (and unfiltered) with/without angle brackets.
  def fetch_mailgun_stored_event
    lookup_log = []

    MAILGUN_LOOKUP_ROUNDS.times do |attempt|
      mailgun_message_id_variants.each do |message_id|
        %w[stored accepted].each do |event|
          item, resp = mailgun_events_lookup(message_id: message_id, event: event)
          lookup_log << mailgun_lookup_attempt(attempt, message_id, event, resp, item)
          return [item, lookup_log] if item.present?
        end

        item, resp = mailgun_events_lookup(message_id: message_id)
        lookup_log << mailgun_lookup_attempt(attempt, message_id, nil, resp, item)
        return [item, lookup_log] if item.present?
      end

      sleep(10 * (2**attempt)) if attempt < MAILGUN_LOOKUP_ROUNDS - 1
    end

    [nil, lookup_log]
  end

  def mailgun_message_id_variants
    [@message_id, "<#{@message_id}>"].uniq
  end

  def mailgun_events_connection
    @mailgun_events_connection ||= Faraday.new(url: "https://api.mailgun.net") do |f|
      f.request :json
      f.response :json
      f.request :authorization, :basic, 'api', ENV['MAILGUN_API_KEY']
      f.options.timeout = 120
      f.options.open_timeout = 120
    end
  end

  def mailgun_events_lookup(message_id:, event: nil)
    params = {
      pretty: 'yes',
      ascending: 'no',
      limit: 1,
      'message-id': message_id
    }
    params[:event] = event if event.present?
    query = params.map { |key, value| "#{key}=#{URI.encode_www_form_component(value)}" }.join('&')
    resp = mailgun_events_connection.get("/v3/#{ENV['SMTP_DOMAIN']}/events?#{query}")
    item = resp.body&.dig('items', 0) if resp.success?
    [item, resp]
  end

  def mailgun_lookup_attempt(attempt, message_id, event, resp, item)
    {
      attempt: attempt,
      message_id: message_id,
      event: event,
      status: resp.status,
      items_count: resp.body.is_a?(Hash) ? resp.body['items']&.size : nil,
      error: resp.body.is_a?(Hash) ? resp.body['error'] : nil,
      found_storage_url: item&.dig('storage', 'url').present?
    }
  end

  # Mailgun URLs may look like `.../storage/abc?name=IMG.heic` (see `?#{att["name"]}`).
  def heic_like_url?(url)
    u = url.to_s.downcase
    return true if u.end_with?('.heic', '.heif')

    q = u.split('?', 2)[1]
    q.present? && (q.end_with?('.heic', '.heif'))
  end

  def heic_temp_extension(url)
    base = url.to_s.downcase.split('?', 2).last
    base.end_with?('.heif') ? '.heif' : '.heic'
  end

  def sanitize_url(url)
    return nil if url.blank?

    SentrySensitiveScrubber.scrub_string(url.to_s)
  end
end
