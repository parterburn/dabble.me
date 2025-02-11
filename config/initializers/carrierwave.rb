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
    def quality(percentage)
      manipulate! do |image|
        image.quality(percentage)
        image
      end
    rescue => error
      Sentry.capture_exception(error, level: "warning")
    end

    def auto_orient
      manipulate! do |image|
        image.auto_orient
        image
      end
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
