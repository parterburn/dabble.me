# Recognizes an image again after it has been re-saved or resized, such as a
# signature logo we stored on an entry once and now see attached to a new
# email. A byte hash can't do that: the stored copy was re-encoded on upload.
#
# The fingerprint is the image's aspect ratio plus a 32x32 grayscale
# thumbnail. Two images match when their aspect ratios agree and their
# thumbnails correlate closely. In testing, re-saving a logo as JPEG kept the
# correlation above 0.99, while different logos of the same shape stayed
# under 0.92 and unrelated photos under 0.91.
class ImageFingerprint
  GRID = 32
  # Decoding at this size first keeps large photos cheap (libvips shrinks on
  # load) and gives an accurate aspect ratio.
  PREVIEW = 256
  MIN_CORRELATION = 0.97
  MAX_ASPECT_DIFFERENCE = 0.03
  # Below this pixel standard deviation an image is close to blank, and too
  # plain to tell apart from other near-blank images.
  MIN_DETAIL = 2.0

  attr_reader :pixels, :aspect_ratio

  def self.from_file(path)
    build { Vips::Image.thumbnail(path.to_s, PREVIEW, height: PREVIEW, size: :down) }
  end

  def self.from_bytes(data)
    return nil if data.blank?

    build { Vips::Image.thumbnail_buffer(data, PREVIEW, height: PREVIEW, size: :down) }
  end

  # Uses the collage downloader, which refuses private and internal hosts.
  def self.from_url(url)
    from_bytes(CollageGenerator.fetch(url))
  end

  def self.build
    image = yield
    aspect_ratio = image.width.to_f / image.height
    image = image.flatten(background: 255) if image.has_alpha?
    image = image.colourspace(:srgb).colourspace(:b_w)[0]
    grid = image.thumbnail_image(GRID, height: GRID, size: :force).cast(:uchar)
    new(pixels: grid.write_to_memory, aspect_ratio: aspect_ratio)
  rescue Vips::Error
    nil
  end
  private_class_method :build

  def initialize(pixels:, aspect_ratio:)
    @pixels = pixels.to_s.b
    @aspect_ratio = aspect_ratio.to_f
  end

  def matches?(other)
    return false if other.nil? || aspect_ratio <= 0 || other.aspect_ratio <= 0
    return false if (aspect_ratio - other.aspect_ratio).abs / [aspect_ratio, other.aspect_ratio].max > MAX_ASPECT_DIFFERENCE

    correlation(other) >= MIN_CORRELATION
  end

  def detailed?
    values.size == GRID * GRID && standard_deviation >= MIN_DETAIL
  end

  def correlation(other)
    a = values
    b = other.values
    return 0.0 if a.empty? || a.size != b.size

    mean_a = a.sum.fdiv(a.size)
    mean_b = b.sum.fdiv(b.size)
    covariance = variance_a = variance_b = 0.0
    a.each_index do |i|
      da = a[i] - mean_a
      db = b[i] - mean_b
      covariance += da * db
      variance_a += da * da
      variance_b += db * db
    end
    return 0.0 if variance_a.zero? || variance_b.zero?

    covariance / Math.sqrt(variance_a * variance_b)
  end

  protected

  def values
    @values ||= pixels.bytes
  end

  private

  def standard_deviation
    mean = values.sum.fdiv(values.size)
    Math.sqrt(values.sum { |v| (v - mean)**2 } / values.size)
  end
end
