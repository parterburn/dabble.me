# frozen_string_literal: true

# Generated images for specs that need real pixels, drawn with shapes so they
# don't depend on installed fonts.
module TestImages
  # A signature-style logo: white background, a red square and two blue bars.
  # variant: 1 moves the bars, for "a different logo of the same shape".
  # Fine noise keeps the file over EmailProcessor's 20KB attachment minimum.
  def signature_logo(width: 300, height: 86, variant: 0)
    image = Vips::Image.black(width, height, bands: 3) + 255
    image = image.draw_rect([200, 40, 40], 0, 0, height, height, fill: true)
    bars = variant.zero? ? [[100, 18, 150, 14], [100, 50, 110, 10]] : [[150, 30, 140, 22], [100, 64, 80, 8]]
    bars.each { |x, y, w, h| image = image.draw_rect([30, 60, 140], x, y, w, h, fill: true) }
    noisy(image)
  end

  def photo_like(seed, width: 640, height: 480)
    low = Vips::Image.gaussnoise(width / 32 + 1, height / 32 + 1, sigma: 50, mean: 128, seed: seed)
    image = low.resize(32, kernel: :cubic).crop(0, 0, width, height)
    noisy(image.bandjoin([image * 0.8, image * 0.6]))
  end

  def blank_image(width: 300, height: 86)
    (Vips::Image.black(width, height, bands: 3) + 255).cast(:uchar).copy(interpretation: :srgb)
  end

  def jpeg_bytes(image, quality: 95)
    image.jpegsave_buffer(Q: quality, strip: true)
  end

  # Re-saves bytes the way ImageUploader stores an upload: fit within
  # 1200px, JPEG at quality 90.
  def stored_copy(bytes)
    Vips::Image.thumbnail_buffer(bytes, 1200, height: 1200, size: :down).jpegsave_buffer(Q: 90)
  end

  def uploaded_image(bytes, filename:, content_type: "image/jpeg")
    file = Tempfile.new(["attachment", File.extname(filename)])
    file.binmode
    file.write(bytes)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: filename, type: content_type)
  end

  private

  def noisy(image)
    (image + Vips::Image.gaussnoise(image.width, image.height, sigma: 6, mean: 0)).cast(:uchar).copy(interpretation: :srgb)
  end
end

RSpec.configure do |config|
  config.include TestImages
end
