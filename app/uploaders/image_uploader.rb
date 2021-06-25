class ImageUploader < CarrierWave::Uploader::Base
  GENERIC_CONTENT_TYPES = %w[application/octet-stream binary/octet-stream]

  storage :fog

  include CarrierWave::MiniMagick

  process :convert_to_jpg, if: :heic_image?
  process :clear_generic_content_type
  process resize_to_limit: [1200, 1200], quality: 90, if: :web_image?
  process :auto_orient, if: :web_image?

  def extension_white_list
    %w(jpg jpeg gif png heic)
  end

  def web_image?(file)
    self.content_type =~ /^image\/(png|jpe?g|gif)$/i || self.content_type == "application/octet-stream"
  end

  def heic_image?(file)
    self.content_type.blank? || self.content_type == "application/octet-stream" || self.content_type == "image/heic" || self.filename =~ /^.+\.(heic|HEIC|Heic)$/i
  end

  def store_dir
    add_dev = "/development" unless Rails.env.production?
    "uploads#{add_dev}/#{model.user.user_key}/#{model.date.strftime("%Y-%m-%d")}"
  end

  def fog_public
    true
  end

  def clear_generic_content_type
    file.content_type = nil if GENERIC_CONTENT_TYPES.include?(file.try(:content_type))
  end  
end
