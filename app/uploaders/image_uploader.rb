require 'carrierwave/processing/mime_types'

class ImageUploader < CarrierWave::Uploader::Base
  storage :fog

  include CarrierWave::MiniMagick
  include CarrierWave::MimeTypes

  after :store, :convert_heic

  process :set_content_type
  process :auto_orient, if: :web_image?
  process resize_to_limit: [1200, 1200], quality: 90, if: :web_image?

  def extension_white_list
    %w(jpg jpeg gif png heic)
  end

  def web_image?(file)
    self.content_type =~ /^image\/(png|jpe?g|gif)$/i
  end

  def store_dir
    add_dev = "/development" unless Rails.env.production?
    "uploads#{add_dev}/#{model.user.user_key}/#{model.date.strftime("%Y-%m-%d")}"
  end

  def fog_public
    true
  end

  def convert_heic(file)
    if self.url && (self.content_type == "image/heic" || self.filename =~ /^.+\.(heic|HEIC|Heic)$/i)
      model.update_attributes(remote_image_url: "https://cdn.filestackcontent.com/#{ENV['FILESTACK_API_KEY']}/output=format:jpg/#{self.url}")
    end
  end
end
