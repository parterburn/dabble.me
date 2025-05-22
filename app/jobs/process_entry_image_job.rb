class ProcessEntryImageJob < ActiveJob::Base
  queue_as :default

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

      unless entry.save && (entry.reload.image_url_cdn == "https://d10r8m94hrfowu.cloudfront.net/uploading.png" || FastImage.type(s3_file.public_url).blank?)
        Sentry.set_user(id: entry.user_id, email: entry.user.email)
        Sentry.capture_message("Error updating entry image", level: :info, extra: { entry_id: entry_id, error: entry.errors.full_messages, fastimage_type: FastImage.type(entry.remote_image_url) })
        url = entry.remote_image_url.presence || entry.image_url_cdn
        EntryMailer.image_error(entry.user, entry, url).deliver_later
      end
      entry.update(filepicker_url: nil) if entry.filepicker_url == "https://d10r8m94hrfowu.cloudfront.net/uploading.png"

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
      entry.update(filepicker_url: nil) if entry.filepicker_url == "https://d10r8m94hrfowu.cloudfront.net/uploading.png"
    end
  rescue => e
    Rails.logger.error "Error processing entry image: #{e.message}"
    entry.update(filepicker_url: nil) if entry.filepicker_url == "https://d10r8m94hrfowu.cloudfront.net/uploading.png"
  end
end
