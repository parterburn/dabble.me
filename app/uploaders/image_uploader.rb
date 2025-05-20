class ImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::Vips

  storage :fog
  process convert: 'jpg', if: :heic_image?
  process resize_to_limit: [1200, 1200, combine_options: { saver: { quality: 90 } }], if: :web_image?

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
