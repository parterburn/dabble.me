class ProcessEntryImageJob < ActiveJob::Base
  queue_as :default

  retry_on Net::ReadTimeout,
           Net::OpenTimeout,
           Faraday::TimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(entry_id, s3_file_key)
    entry = Entry.find_by(id: entry_id)
    return unless entry

    if s3_file_key.present?
      # File was stored temporarily on s3
      s3 = Fog::Storage.new({
        provider:              "AWS",
        aws_access_key_id:     ENV["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
      })
      bucket = s3.directories.new(key: ENV["AWS_BUCKET"])
      s3_file = bucket.files.get(s3_file_key)

      return unless s3_file # Exit if file doesn't exist

      jpeg_file = nil
      data = fog_bytes(s3_file)
      if data.nil?
        @error = "The image could not be read."
      elsif File.extname(s3_file.key).to_s.downcase.in?(%w[.heic .heif])
        jpeg_file = assign_converted_heic(entry, data, s3_file.key)
      else
        type = sniffed_image_type(data, s3_file.content_type)
        if type
          entry.image = uploaded_image(data, stored_filename(s3_file.key, type), type)
        else
          @error = "The file was not an image."
        end
      end

      unless entry.save
        @error = entry.errors.full_messages.to_sentence
      end

      entry.reload
      if entry.image.blank?
        error_messages = @error.present? ? [@error] : ['The image could not be saved. Please try uploading again via the web interface.']
        Sentry.set_user(id: entry.user_id, email: entry.user.email)
        Sentry.capture_message("Error updating entry image", level: :info, extra: { entry_id: entry_id, url: s3_file.public_url, error_messages: error_messages })
        # Persist the error on the entry so the logged-in user sees a banner
        # on their next page view (see ImageCollageJob for the rationale).
        entry.update(image_error: error_messages.to_sentence.presence)
        cache_key = "process_entry_image_error_email_sent:#{entry_id}"
        unless Rails.cache.read(cache_key)
          EntryMailer.image_error(entry.user, entry, "single", error_messages).deliver_later
          Rails.cache.write(cache_key, true, expires_in: 1.hour)
        end
      else
        entry.update(image_error: nil) if entry.image_error.present?
      end

      entry.update(uploading_image: false) if entry.uploading_image?

      begin
        bucket.files.new(key: s3_file_key).destroy
      rescue => e
        Rails.logger.error "Failed to delete S3 file: #{e.message}"
      end

      if jpeg_file.present?
        jpeg_file.tempfile.close
        jpeg_file.tempfile.unlink rescue nil
      end
    else
      entry.update(uploading_image: false) if entry.uploading_image?
    end
  rescue Net::ReadTimeout, Net::OpenTimeout, Faraday::TimeoutError => e
    Rails.logger.error "Error processing entry image: #{e.message}"
    clear_uploading_placeholder(entry_id)
    raise
  rescue => e
    Rails.logger.error "Error processing entry image: #{e.message}"
    clear_uploading_placeholder(entry_id)
  end

  private

  def fog_bytes(s3_file)
    body = s3_file.body
    data = body.respond_to?(:read) ? body.read : body
    data.to_s.b
  rescue StandardError => e
    Rails.logger.error "Failed to read stored image: #{e.class}"
    nil
  end

  def assign_converted_heic(entry, data, key)
    temp_file = nil
    temp_file = Tempfile.new(["heic_image", File.extname(key)])
    temp_file.binmode
    temp_file.write(data)
    temp_file.rewind
    converted = ImageConverter.new(tempfile: temp_file, width: 1200).call
    uploaded = uploaded_image(converted, "#{File.basename(key, '.*')}.jpg", "image/jpeg")
    entry.image = uploaded
    uploaded
  rescue StandardError => e
    Rails.logger.error "Failed to convert HEIC to JPEG: #{e.class}"
    type = sniffed_image_type(data, "image/heic")
    return nil unless type

    uploaded_image(data, stored_filename(key, type), type).tap { |file| entry.image = file }
  ensure
    temp_file&.close
    temp_file&.unlink
  end

  def sniffed_image_type(data, declared)
    fast = FastImage.type(StringIO.new(data.to_s))
    mapped = {
      jpeg: "image/jpeg",
      png: "image/png",
      gif: "image/gif",
      webp: "image/webp",
      heic: "image/heic",
      heif: "image/heif"
    }[fast]
    return mapped if mapped && Entry::ALLOWED_IMAGE_TYPES.include?(mapped)

    declared = declared.to_s.downcase.split(";").first.to_s.strip
    return declared if Entry::ALLOWED_IMAGE_TYPES.include?(declared)

    nil
  end

  def stored_filename(key, type)
    ext = {
      "image/jpeg" => ".jpg",
      "image/jpg" => ".jpg",
      "image/png" => ".png",
      "image/gif" => ".gif",
      "image/webp" => ".webp",
      "image/heic" => ".heic",
      "image/heif" => ".heif"
    }[type]
    "#{File.basename(key, '.*')}#{ext || File.extname(key)}"
  end

  def uploaded_image(io_or_bytes, filename, type)
    tempfile = if io_or_bytes.respond_to?(:path) && io_or_bytes.respond_to?(:read)
      io_or_bytes
    else
      file = Tempfile.new(["entry-image", File.extname(filename.to_s)])
      file.binmode
      file.write(io_or_bytes)
      file.rewind
      file
    end
    ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: filename, type: type)
  end

  def clear_uploading_placeholder(entry_id)
    entry = Entry.find_by(id: entry_id)
    entry&.update(uploading_image: false) if entry&.uploading_image?
  end
end
