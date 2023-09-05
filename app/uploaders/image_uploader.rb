class ImageUploader < CarrierWave::Uploader::Base
  GENERIC_CONTENT_TYPES = %w[application/octet-stream binary/octet-stream]

  storage :fog

  include CarrierWave::MiniMagick

  process :clear_generic_content_type
  process :convert_to_jpg, if: :heic_image?
  process :convert_to_jpg, if: :webp_image?
  process resize_to_limit: [1200, 1200], quality: 90, if: :web_image?
  process :auto_orient, if: :web_image?

  # def extension_allowlist
  #   %w(jpg jpeg gif png heic heif)
  # end

  def content_type_allowlist
    [/(image|application)\/(png|jpe?g|gif|webp|heic|heif|octet-stream)/]
  end

  def web_image?(file)
    heic_image?(file) || self.content_type =~ /^image\/(png|jpe?g|webp|gif)$/i || self.content_type == "application/octet-stream"
  end

  def heic_image?(file)
    self.content_type.blank? || self.content_type == "application/octet-stream" || self.content_type == "image/heic" || self.content_type == "image/heif" || self.filename =~ /^.+\.(heic|HEIC|Heic|heif|HEIF|Heif)$/i
  end

  def webp_image?(file)
    self.content_type == "image/webp" || self.filename =~ /^.+\.(Webp|webp|WEBP)$/i
  end

  def store_dir
    add_dev = "/development" unless Rails.env.production?
    "uploads#{add_dev}/#{model.user.user_key}/#{model.date.strftime("%Y-%m-%d")}"
  end

  def clear_generic_content_type
    file.content_type = nil if GENERIC_CONTENT_TYPES.include?(file.try(:content_type))
  end

  def full_filename(file)
    filename = super(file)
    filename.gsub(/\.heic/i, ".jpg").gsub(/\.heif/i, ".jpg")
  end

  def filename
    super.gsub(/\.heic/i, ".jpg").gsub(/\.heif/i, ".jpg") if original_filename.present?
  end
end
