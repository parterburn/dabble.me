class ImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick

  GENERIC_CONTENT_TYPES = %w[application/octet-stream binary/octet-stream]

  storage :fog

  process :clear_generic_content_type
  process :convert_to_jpg, if: :heic_image?
  process :auto_orient, if: :web_image?
  process size_and_optimize: [{resize_to: "1200x1200>", quality: "95"}], if: :web_image?

  # def extension_allowlist
  #   %w(jpg jpeg gif png heic heif)
  # end

  def process!(new_file=nil)
    begin
      file_to_process = new_file || file
      file_to_process = file_to_process.loader(page: 0) if pdf?(file_to_process)
      @original_width, @original_height = original_dimensions(file_to_process)
      super
    rescue => error
      # Always save the entry, even if the image processing fails
      # set the image to nil
      model.image = nil
      model.save!
      Sentry.capture_exception(error)
    end
  end

  def content_type_allowlist
    [/(image|application)\/(png|jpe?g|gif|webp|heic|heif|octet-stream)/]
  end

  def web_image?(file)
    (
      @original_width && @original_height && @original_width.to_i < 8000 && @original_height.to_i < 8000
    ) &&
      (
        !!(file.content_type =~ /^image\/(png|jpe?g|webp|gif|heic|heif)$/i) ||
        !!(file.filename =~ /\.(png|jpe?g|webp|gif|heic|heif)$/i)
      )
  end

  def pdf?(file)
    file.content_type == 'application/pdf'
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

  def clear_generic_content_type
    file.content_type = nil if GENERIC_CONTENT_TYPES.include?(file.try(:content_type))
  end

  # def full_filename(file)
  #   fname = super(file)
  #   fname.gsub(/\.heic/i, ".jpg").gsub(/\.heif/i, ".jpg")
  # end

  # def filename
  #   return super unless original_filename.present?

  #   basename = File.basename(original_filename, '.*')
  #   "#{basename}.jpg"
  # end

  def original_dimensions(file)
    # Add timeout protection for MiniMagick
    Timeout.timeout(10) do
      image = MiniMagick::Image.open(file.path)
      [image.width, image.height]
    end
  rescue Timeout::Error
    Rails.logger.error("Timeout getting image dimensions for #{file.path}")
    [nil, nil]
  rescue StandardError => e
    Rails.logger.error("Error getting image dimensions: #{e.message}")
    [nil, nil]
  end
end
