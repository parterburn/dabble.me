class ImageConverter
  def initialize(tempfile:, width: nil, height: nil, type: 'jpg')
    @tempfile = tempfile
    @width = width
    @height = height
    @type = type
  end

  def call
    ImageProcessing::Vips.source(@tempfile)
                         .resize_to_limit(@width, @height)
                         .convert(@type)
                         .call
  end
end
