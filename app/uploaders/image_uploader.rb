class ImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::Vips

  storage :fog

  version :jpeg, if: :heic_image? do
    process :safe_convert_to_jpg
  end

  # Add rescue block around resize operation
  process :safe_resize, if: :web_image?

  def safe_convert_to_jpg
    begin
      convert(:jpg)
    rescue => e
      Sentry.capture_exception(e, extra: { type: "HEIC to JPEG conversion failed" })
      # Continue without conversion rather than failing entirely
    end
  end

  def safe_resize(*)
    begin
      resize_to_limit(1200, 1200, combine_options: { saver: { quality: 90 } })
    rescue => e
      Sentry.capture_exception(e, extra: { type: "Image resize failed" })
      # Continue without resizing rather than failing entirely
    end
  end

  def url(*args)
    if version_active?(:jpeg)
      jpeg.url(*args)
    else
      super
    end
  end

  def content_type_allowlist
    [/(image|application)\/(png|jpe?g|gif|webp|heic|heif|octet-stream)/]
  end

  def web_image?(file)
    (
      !!(file.content_type =~ /^image\/(png|jpe?g|webp|gif|heic|heif)$/i) ||
      !!(file.filename =~ /\.(png|jpe?g|webp|gif|heic|heif)$/i)
    )
  end

  def heic_image?(new_file)
    # Detect HEIC/HEIF by MIME type or file extension on the original filename
    content_type = new_file&.content_type.to_s
    original_name = new_file.respond_to?(:filename) ? new_file.filename.to_s : ""
    ext = File.extname(original_name).downcase
    # Match image/heic, image/heif MIME types or .heic/.heif extensions
    content_type.in?(%w[image/heic image/heif]) || ext.in?(%w[.heic .heif])
  end

  def store_dir
    add_dev = "/development" unless Rails.env.production?
    "uploads#{add_dev}/#{model.user.user_key}/#{model.date.strftime("%Y-%m-%d")}"
  end
end
