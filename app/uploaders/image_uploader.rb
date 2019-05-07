class ImageUploader < CarrierWave::Uploader::Base
  GENERIC_CONTENT_TYPES = %w[application/octet-stream binary/octet-stream]

  storage :fog

  include CarrierWave::MiniMagick

  after :store, :convert_heic

  process :clear_generic_content_type
  process resize_to_limit: [1200, 1200], quality: 90, if: :web_image?
  process :auto_orient

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
      model.remote_image_url = "https://cdn.filestackcontent.com/#{ENV['FILESTACK_API_KEY']}/output=format:jpg/#{self.url}"
      model.save
    end
  end

  def clear_generic_content_type
    file.content_type = nil if GENERIC_CONTENT_TYPES.include?(file.try(:content_type))
  end  
end
