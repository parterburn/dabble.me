class ProcessEntryImageJob < ActiveJob::Base
  queue_as :default

  retry_on Net::ReadTimeout,
           Net::OpenTimeout,
           Faraday::TimeoutError,
           wait: :exponentially_longer,
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
      temp_file = nil

      # Convert HEIC to JPEG if needed
      if File.extname(s3_file.key)&.downcase == ".heic"
        require 'open-uri'
        begin
          # Download the file to a temporary file
          temp_file = Tempfile.new(['heic_image', '.heic'])
          temp_file.binmode
          temp_file.write(URI.open(s3_file.public_url).read)
          temp_file.rewind

          tempfile = ImageConverter.new(tempfile: temp_file, width: 1200).call
          jpeg_file = ActionDispatch::Http::UploadedFile.new(
            {
              filename: "#{s3_file.key.split('.').first}.jpg",
              tempfile: tempfile,
              type: 'image/jpg',
              head: "Content-Disposition: form-data; name=\"property[images][]\"; filename=\"#{s3_file.key.split('.').first}.jpg\"\r\nContent-Type: image/jpg\r\n"
            }
          )

          entry.image = jpeg_file
        rescue => e
          Rails.logger.error "Failed to convert HEIC to JPEG: #{e.message}"
          # Fall back to using the original file
          entry.remote_image_url = s3_file.public_url
        ensure
          # Clean up temp file if it exists
          temp_file&.close
          temp_file&.unlink
        end
      else
        entry.remote_image_url = s3_file.public_url
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

  def clear_uploading_placeholder(entry_id)
    entry = Entry.find_by(id: entry_id)
    entry&.update(uploading_image: false) if entry&.uploading_image?
  end
end
