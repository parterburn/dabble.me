class ProcessEntryImageJob < ActiveJob::Base
  queue_as :default

  def perform(entry_id, attachment_info)
    entry = Entry.find_by(id: entry_id)
    return unless entry

    if attachment_info[:temp_file_path].present?
      # File was stored temporarily on disk
      file = File.open(attachment_info[:temp_file_path])

      # Convert HEIC to JPEG if needed
      if File.extname(attachment_info[:original_filename])&.downcase == ".heic"
        begin
          tempfile = ImageConverter.new(tempfile: file, width: 1200).call
          jpeg_file = ActionDispatch::Http::UploadedFile.new(
            {
              filename: "#{attachment_info[:original_filename].split('.').first}.jpg",
              tempfile: tempfile,
              type: 'image/jpg',
              head: "Content-Disposition: form-data; name=\"property[images][]\"; filename=\"#{attachment_info[:original_filename].split('.').first}.jpg\"\r\nContent-Type: image/jpg\r\n"
            }
          )

          entry.image = jpeg_file
        rescue => e
          Rails.logger.error "Failed to convert HEIC to JPEG: #{e.message}"
          # Fall back to using the original file
          entry.image = file
        end
      else
        entry.image = file
      end

      entry.filepicker_url = nil if entry.filepicker_url == "https://d10r8m94hrfowu.cloudfront.net/uploading.png"
      entry.save

      # Clean up temp file
      file.close
      FileUtils.rm_f(attachment_info[:temp_file_path]) if File.exist?(attachment_info[:temp_file_path])
    else
      entry.update(filepicker_url: nil) if entry.filepicker_url == "https://d10r8m94hrfowu.cloudfront.net/uploading.png"
    end
  rescue => e
    Rails.logger.error "Error processing entry image: #{e.message}"
    entry.update(filepicker_url: nil) if entry.filepicker_url == "https://d10r8m94hrfowu.cloudfront.net/uploading.png"
    # Clean up temp file if it exists
    FileUtils.rm_f(attachment_info[:temp_file_path]) if attachment_info[:temp_file_path].present? && File.exist?(attachment_info[:temp_file_path])
  end
end
