class ImageCollageJob < ActiveJob::Base
  queue_as :default

  # Sidekiq will retry unhandled exceptions by default. We make timeouts explicit here
  # so we can control retry timing and attempts for transient network issues.
  retry_on Net::ReadTimeout,
           Faraday::TimeoutError,
           wait: :exponentially_longer,
           attempts: 6

  def perform(entry_id, urls: nil, message_id: nil)
    entry = Entry.where(id: entry_id).first
    @error = nil
    return nil unless entry.present?

    @message_id = message_id
    @user = entry.user

    @existing_url = entry.image.present? ? entry.image_url_cdn(cloudflare: false) : nil
    entry.update(uploading_image: true)

    collage_url = if @message_id.present?
      collage_from_mailgun_attachments
    else
      collage_from_urls(urls + [@existing_url])
    end

    # We still fetch the final image into a Tempfile before handing it to CarrierWave
    # so we control timeouts explicitly (SsrfFilter's defaults can be short on some stacks).
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
      Sentry.set_user(id: @user.id, email: @user.email)
      Sentry.capture_message("Error updating collage image", level: :info, extra: { entry_id: entry_id, error_messages: error_messages, url: collage_url })
      # Persist the error on the entry so the logged-in user sees a banner on
      # their next page view. The job runs async after the request is gone,
      # so we can't use `flash` — the entry itself is the durable channel.
      entry.update(image_error: error_messages.to_sentence.presence)
      # Only send one error email per entry per hour; job can retry up to 6 times and would otherwise send 6 emails.
      cache_key = "image_collage_error_email_sent:#{entry_id}"
      unless Rails.cache.read(cache_key)
        EntryMailer.image_error(@user, entry, "collage", error_messages).deliver_later
        Rails.cache.write(cache_key, true, expires_in: 1.hour)
      end
    else
      # Success — clear any leftover banner from a prior failed attempt so the
      # user isn't shown a stale error over their new collage.
      entry.update(image_error: nil) if entry.image_error.present?
    end
    entry.update(uploading_image: false) if entry.uploading_image?
  end

  # Download the collage URL into a Tempfile with explicit timeouts.
  # Returns a Tempfile on success (caller must close/unlink after use), nil on failure.
  def fetch_collage_image(url)
    return nil if url.blank?

    conn = Faraday.new do |f|
      f.options.open_timeout = 15
      f.options.timeout = 45
    end
    response = conn.get(url)
    return nil unless response.success?

    tempfile = Tempfile.new(['collage', '.jpg'])
    tempfile.binmode
    tempfile.write(response.body)
    tempfile.rewind
    tempfile
  rescue URI::InvalidURIError, StandardError => e
    Sentry.capture_exception(e, extra: { url: url })
    nil
  end

  def collage_from_mailgun_attachments
    @error = "No message ID found" unless @message_id.present?
    return unless @message_id.present?

    last_message = nil
    message = nil
    5.times do
      connection = Faraday.new(url: "https://api.mailgun.net") do |f|
        f.request :json
        f.response :json
        f.request :authorization, :basic, 'api', ENV['MAILGUN_API_KEY']
        f.options.timeout = 120
        f.options.open_timeout = 120
      end
      resp = connection.get("/v3/#{ENV['SMTP_DOMAIN']}/events?pretty=yes&event=accepted&ascending=no&limit=1&message-id=#{URI.encode_www_form_component(@message_id)}")
      last_message = resp.body&.dig("items", 0) if resp.success?
      break if last_message.present?
      sleep 10
    end
    @error = "No last message found" unless last_message.present?
    return unless last_message.present?

    message = nil
    5.times do
      message_url = URI.parse(last_message["storage"]["url"])
      msg_conn = Faraday.new("https://#{message_url.host}") do |f|
        f.options.timeout = 120
        f.options.open_timeout = 120
        f.request :json
        f.response :json
        f.request :authorization, :basic, 'api', ENV['MAILGUN_API_KEY']
      end
      response = msg_conn.get(message_url.path)
      message = response.body if response.success?
      break if message.present?
      sleep 10
    end
    @error = "No message found" unless message.present?
    @error = "Message not from user" unless message["recipients"].to_s.include?(@user.user_key) || message["from"].to_s.include?(@user.email)
    return unless message.present? && message["recipients"].to_s.include?(@user.user_key) || message["from"].to_s.include?(@user.email)

    attachment_urls = message["attachments"].map do |att|
      next unless Entry::ALLOWED_IMAGE_TYPES.include?(att["content-type"]&.downcase)
      next unless att["size"].to_i > 20_000 # ignore tiny attachments

      "#{att["url"].gsub("://", "://api:#{ENV['MAILGUN_API_KEY']}@")}?#{att["name"]}"
    end.compact_blank

    @error = "No attachments found" unless attachment_urls.any?
    return nil unless attachment_urls.any?

    collage_from_urls(attachment_urls + [@existing_url])
  end

  def collage_from_urls(urls)
    return nil unless urls.present?

    urls.reject! { |url| url.is_a?(String) && url&.include?("googleusercontent.com/mail-sig/") }

    urls = urls.map do |url|
      next if url.blank?

      if url.downcase.ends_with?(".heic")
        begin
          if url.include?("@")
            uri = URI.parse(url)
            conn = Faraday.new(uri.scheme + "://" + uri.host) do |f|
              f.options.timeout = 120
              f.options.open_timeout = 120
              f.request :authorization, :basic, "api", ENV['MAILGUN_API_KEY']
            end
            response = conn.get(uri.path)
            tempfile = Tempfile.new(['attachment', ".heic"])
            tempfile.binmode
            tempfile.write(response.body)
            tempfile.rewind
            result = ImageConverter.new(tempfile: tempfile, width: 1200, user: @user).s3_url
            tempfile.close
            tempfile.unlink
            result
          else
            file = URI.parse(url).open
            ImageConverter.new(tempfile: file, width: 1200, user: @user).s3_url
          end
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
      CollageGenerator.new(urls: urls, user: @user).s3_url
    end
  end
end
