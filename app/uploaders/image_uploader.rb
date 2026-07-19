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
      Rails.logger.error "HEIC to JPEG conversion failed: #{e.message}"
      Sentry.capture_exception(e, extra: { type: "HEIC to JPEG conversion failed" })
      # Continue without conversion rather than failing entirely
    end
  end

  def safe_resize(*)
    begin
      # Use format-specific options to avoid compression issues
      if heic_image?(file)
        # For HEIC/HEIF files, use simpler resize without quality settings
        resize_to_limit(1200, 1200)
      else
        # For other formats, use quality settings
        resize_to_limit(1200, 1200, combine_options: { saver: { quality: 90 } })
      end
    rescue => e
      Sentry.capture_exception(e, extra: { type: "Image resize failed" })
      # Continue without resizing rather than failing entirely
    end
  end

  def url(*args)
    if version_active?(:jpeg) && jpeg.file.exists?
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
    # Detect HEIC/HEIF by MIME type or file extension on the original filename.
    # Avoid ActiveSupport blank? on Fog files — that calls exists? and HEADs S3.
    return false if new_file.nil?

    content_type = begin
      new_file.respond_to?(:content_type) ? new_file.content_type.to_s : ''
    rescue StandardError
      ''
    end
    original_name = begin
      if new_file.respond_to?(:filename)
        new_file.filename.to_s
      elsif new_file.respond_to?(:path)
        File.basename(new_file.path.to_s)
      else
        ''
      end
    rescue StandardError
      ''
    end
    ext = File.extname(original_name).downcase
    content_type.in?(%w[image/heic image/heif]) || ext.in?(%w[.heic .heif])
  end

  def store_dir
    store_dir_for(model.date)
  end

  # CarrierWave store paths include the entry date. When that date changes,
  # URLs point at a new key while the object remains under the old key unless
  # we move it. Call this before the new date is persisted.
  def relocate_between_dates!(from_date, to_date)
    return if from_date.blank? || to_date.blank?
    return if from_date.to_date == to_date.to_date

    filename = model.read_attribute(mounted_as).presence
    return if filename.blank?

    old_dir = store_dir_for(from_date)
    new_dir = store_dir_for(to_date)

    filenames_to_move(filename).each do |name|
      move_stored_key!("#{old_dir}/#{name}", "#{new_dir}/#{name}")
    end
  end

  def store_dir_for(date)
    add_dev = "/development" unless Rails.env.production?
    "uploads#{add_dev}/#{model.user.user_key}/#{date.strftime('%Y-%m-%d')}"
  end

  private

  def filenames_to_move(filename)
    names = [filename]
    # CarrierWave stores versions as "#{version_name}_#{parent_filename}" in the
    # same directory (e.g. jpeg_photo.heic for HEIC conversions).
    versions.each_key do |version_name|
      names << "#{version_name}_#{filename}"
    end
    names.uniq
  end

  def move_stored_key!(old_key, new_key)
    return if old_key == new_key

    storage = CarrierWave::Storage::Fog.new(self)
    old_file = CarrierWave::Storage::Fog::File.new(self, storage, old_key)
    return unless old_file.exists?

    old_file.copy_to(new_key)
    old_file.delete
  rescue => e
    Rails.logger.error("Failed to relocate image from #{old_key} to #{new_key}: #{e.message}")
    Sentry.capture_exception(e, extra: { type: "Image relocate failed", old_key: old_key, new_key: new_key, entry_id: model.id })
    raise
  end
end
