class ImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick

  process :auto_orient
  process resize_to_limit: [1200, 1200], quality: 90

  def extension_white_list
    %w(jpg jpeg gif png)
  end

  def store_dir
    add_dev = "/development" unless Rails.env.production?
    "uploads#{add_dev}/#{model.user.user_key}/#{model.date.strftime("%Y-%m-%d")}"
  end

  def fog_public
    true
  end
end