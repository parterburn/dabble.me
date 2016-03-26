class ImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick

  process :auto_orient
  process resize_to_limit: [1200, 1200], quality: 90

  def extension_white_list
    %w(jpg jpeg gif png)
  end

  def filename
    "#{hash}.#{file.extension}" if original_filename.present?
  end

  def store_dir
    "uploads/#{model.user.user_key}"
  end  

  def fog_public
    true
  end

  private

  def hash
    Digest::SHA1.hexdigest file_contents
  end

  def file_contents
    read
  end
end