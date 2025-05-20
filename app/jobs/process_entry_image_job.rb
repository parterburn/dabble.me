class ProcessEntryImageJob < ActiveJob::Base
  queue_as :default

  def perform(entry_id, attachment_data:)
    entry = Entry.find_by(id: entry_id)
    return unless entry

    if Entry::ALLOWED_IMAGE_TYPES.include?(Marcel::MimeType.for(attachment_data[:data]))
      Tempfile.create(['entry_image', File.extname(attachment_data[:original_filename])&.downcase&.gsub(".heic", ".jpg")]) do |tempfile|
        tempfile.binmode
        tempfile.write(Base64.strict_decode64(attachment_data[:data]))
        tempfile.rewind

        # Convert HEIC to JPEG if needed
        if File.extname(attachment_data[:original_filename])&.downcase == ".heic"
          begin
            require "image_processing/vips"
            attachment_data[:original_filename] = attachment_data[:original_filename].gsub(/\.heic$/i, '.jpg')
            processed = ImageProcessing::Vips
              .source(tempfile.path)
              .convert("jpg")
              .resize_to_limit(1200, 1200)
              .saver(strip: true)
              .call

            entry.image = processed
          rescue => e
            Rails.logger.error "Failed to convert HEIC to JPEG: #{e.message}"
            # Fall back to using the original file
            entry.image = tempfile
          end
        else
          entry.image = tempfile
        end

        entry.filepicker_url = nil if entry.filepicker_url == "https://d10r8m94hrfowu.cloudfront.net/uploading.png"
        entry.save
      end
    else
      entry.update(filepicker_url: nil) if entry.filepicker_url == "https://d10r8m94hrfowu.cloudfront.net/uploading.png"
    end
  rescue => e
    Rails.logger.error "Error processing entry image: #{e.message}"
    entry.update(filepicker_url: nil) if entry.filepicker_url == "https://d10r8m94hrfowu.cloudfront.net/uploading.png"
  end
end
