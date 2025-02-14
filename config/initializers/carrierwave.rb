CarrierWave.configure do |config|
  config.fog_credentials = {
    provider:              "AWS",
    aws_access_key_id:     ENV["AWS_ACCESS_KEY_ID"],
    aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
  }

  config.fog_directory = ENV["AWS_BUCKET"]
  config.fog_public = true
  config.fog_attributes = { content_disposition: "inline", cache_control: "public, max-age=#{365.days.to_i}" }
  config.validate_download = false
end

module CarrierWave
  module MiniMagick
    def size_and_optimize(resize_to: nil, quality: "90")
      manipulate! do |img|
        img.resize resize_to if resize_to.present?
        img.strip
        img.quality quality
        img.interlace "plane"
        img = yield(img) if block_given?
        img
      end
    rescue => error
      Sentry.capture_exception(error, level: "warning")
    end

    def auto_orient
      manipulate! do |image|
        image.auto_orient
        image = yield(image) if block_given?
        image
      end
    rescue CarrierWave::ProcessingError => e
      Sentry.capture_exception(e,
        extra: {
          mime_type: file&.content_type,
          original_filename: file&.original_filename
        },
        level: "warning"
      )
      # Return original file without orientation to prevent upload failure
      retrieve_from_cache!(cached_filename) if cached_filename
    rescue => error
      Sentry.capture_exception(error, level: "warning")
    end

    def convert_to_jpg
      manipulate! do |image|
        image.format("jpg")
        image
      end
    rescue => error
      Sentry.capture_exception(error, level: "warning")
    end
  end
end
