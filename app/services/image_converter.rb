class ImageConverter
  def initialize(tempfile:, width: nil, height: nil, type: 'jpg', user:)
    @tempfile = tempfile
    @width = width
    @height = height
    @type = type
    @user = user
  end

  def call
    ImageProcessing::Vips.source(@tempfile)
                         .resize_to_limit(@width, @height)
                         .convert(@type)
                         .call
  end

  def s3_url
    tempfile = call
    filename = "#{SecureRandom.uuid}.jpg"
    jpeg_file = ActionDispatch::Http::UploadedFile.new(
      {
        filename: filename,
        tempfile: tempfile,
        type: 'image/jpg',
        head: "Content-Disposition: form-data; name=\"property[images][]\"; filename=\"#{filename}\"\r\nContent-Type: image/jpg\r\n"
      }
    )

    add_dev = "/development" unless Rails.env.production?
    folder = "uploads#{add_dev}/#{@user.id}/collages/#{Date.today.strftime("%Y-%m-%d")}/"
    file_key = "#{folder}#{filename}"
    file = UploadToS3.new(file_key: file_key, body: jpeg_file.read).call
    jpeg_file.tempfile.close
    jpeg_file.tempfile.unlink rescue nil

    file.public_url
  end
end
