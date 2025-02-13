class ImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick

  GENERIC_CONTENT_TYPES = %w[application/octet-stream binary/octet-stream]

  storage :fog

  process :convert_to_jpg, if: :heic_image?
  process :clear_generic_content_type
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
        heic_image?(file) ||
        !!(file.content_type =~ /^image\/(png|jpe?g|webp|gif)$/i) ||
        !!(file.filename =~ /\.(png|jpe?g|webp|gif)$/i)
      )
  end

  def pdf?(file)
    file.content_type == 'application/pdf'
  end

  def heic_image?(file)
    self.content_type.blank? || self.content_type == "application/octet-stream" || self.content_type == "image/heic" || self.content_type == "image/heif" || !!(self.filename =~ /^.+\.(heic|HEIC|Heic|heif|HEIF|Heif)$/i)
  end

  # def webp_image?(file)
  #   self.content_type == "image/webp" || self.filename =~ /^.+\.(Webp|webp|WEBP)$/i
  # end

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
    super.gsub(/\.heic/i, ".jpg").gsub(/\.heif/i, ".jpg")
  end

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
