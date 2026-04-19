require "net/http"
require "uri"

# Builds a JPEG collage from a list of image URLs using libvips.
#
# Layout: per-count "row plan" (see ROW_PLANS + `row_plan`) so the output has
# no empty padding tiles for 2..9 images. Canvas WIDTH is fixed at @size and
# HEIGHT floats based on the source photos' aspect ratios, so three landscapes
# produce a near-square output instead of a thin strip inside a huge square
# canvas. Tiles are cover-cropped to exactly fill each cell using libvips'
# attention-based crop (centers the crop on salient features like faces);
# because each row's cell height is derived from the actual content, crop
# loss is typically zero for uniform rows and small for mixed rows. White
# SHIM separates tiles and an outer margin mattes the whole canvas. Duplicate
# URLs are collapsed.
class CollageGenerator
  MAX_IMAGES = 16
  DEFAULT_SIZE = 1200
  JPEG_QUALITY = 88
  HTTP_OPEN_TIMEOUT = 15
  HTTP_READ_TIMEOUT = 60
  MAX_REDIRECTS = 5
  # One refetch is enough to absorb the typical failure mode — S3 just-PUT
  # consistency lag or a flaky proxy truncating the body. More than one is
  # mostly wasted work on genuinely corrupt objects.
  MAX_TRUNCATION_RETRIES = 1
  TRUNCATION_RETRY_DELAY = 1 # seconds

  # Gutter (px) between tiles AND around the outer canvas edge. White.
  SHIM = 16
  BACKGROUND = [255, 255, 255].freeze

  # Hand-tuned row breakdowns that fill the grid completely (no empty cells).
  # Each entry is the list of tiles-per-row. N=2 and N=3 are picked dynamically
  # based on input orientation (see `row_plan`). For N > 9 we fall back to a
  # square-ish auto grid.
  ROW_PLANS = {
    1 => [1],
    4 => [2, 2],
    5 => [2, 3],
    6 => [3, 3],
    7 => [3, 4],
    8 => [4, 4],
    9 => [3, 3, 3]
  }.freeze

  # Clamp each row's computed height so one wildly-proportioned input can't
  # produce a comical strip. Expressed as tile-aspect bounds: row_h is floored
  # at cell_w / MAX_TILE_ASPECT and ceilinged at cell_w * MAX_TILE_PORTRAIT.
  MAX_TILE_ASPECT = 3.0    # no tile flatter than 3:1 (w:h)
  MAX_TILE_PORTRAIT = 2.0  # no tile taller than 1:2 (w:h)

  def initialize(urls:, size: DEFAULT_SIZE, user: nil)
    @urls = Array(urls).compact_blank.uniq.first(MAX_IMAGES)
    @size = size
    @user = user
  end

  # Builds the collage and returns a Tempfile. Caller must close/unlink.
  # Returns nil if no usable source images.
  def tempfile
    return nil if @urls.empty?

    images = @urls.map { |u| load_image(u) }.compact
    return nil if images.empty?

    grid = build_grid(images)

    tf = Tempfile.new(["collage", ".jpg"])
    tf.binmode
    grid.jpegsave(tf.path, Q: JPEG_QUALITY, strip: true)
    tf.rewind
    tf
  rescue StandardError => e
    Sentry.capture_exception(e, extra: { url_count: @urls.size })
    nil
  end

  # Builds the collage, uploads the JPEG to S3, and returns the public URL.
  # Returns nil on failure.
  def s3_url
    tf = tempfile
    return nil unless tf

    add_dev = "/development" unless Rails.env.production?
    user_segment = @user ? "#{@user.id}/" : ""
    folder = "uploads#{add_dev}/#{user_segment}collages/#{Date.today.strftime('%Y-%m-%d')}/"
    file_key = "#{folder}#{SecureRandom.uuid}.jpg"
    UploadToS3.new(file_key: file_key, body: File.binread(tf.path)).call.public_url
  ensure
    tf&.close
    begin
      tf&.unlink
    rescue StandardError
      nil
    end
  end

  private

  def build_grid(images)
    plan = row_plan(images)
    inner_w = @size - (2 * SHIM)

    # For each row, derive its height from the photos that live in it so the
    # canvas ends up at a natural aspect — three landscapes in one row no
    # longer sit in a tall square canvas surrounded by dead white space, and
    # a single portrait doesn't get letterboxed into a wide square.
    idx = 0
    rows = plan.map do |cols|
      cell_w = (inner_w - ((cols - 1) * SHIM)) / cols
      row_imgs = images[idx, cols]
      idx += cols

      # Each image's "natural" height at this cell width. The row shares one
      # height, so we average — this bounds per-tile crop to the spread of
      # aspects within the row (uniform rows → ~zero crop; mixed rows → a
      # mild, attention-centered crop on the outliers).
      naturals = row_imgs.map { |img| (cell_w.to_f * img.height / img.width).round }
      avg = naturals.sum / naturals.size
      row_h = avg.clamp((cell_w / MAX_TILE_ASPECT).round, (cell_w * MAX_TILE_PORTRAIT).round)

      tiles = row_imgs.map { |img| prepare_tile(img, cell_w, row_h) }
      [Vips::Image.arrayjoin(tiles, across: cols, shim: SHIM, background: BACKGROUND), row_h]
    end

    grid = Vips::Image.arrayjoin(rows.map(&:first), across: 1, shim: SHIM, background: BACKGROUND, halign: "centre")

    total_h = rows.sum { |_, h| h } + ((rows.size - 1) * SHIM) + (2 * SHIM)
    ox = ((@size - grid.width) / 2.0).round
    oy = SHIM
    grid.embed(ox, oy, @size, total_h, extend: :background, background: BACKGROUND)
  end

  # How many tiles each row should contain, summing to `images.size`.
  #
  # N=2 and N=3 are orientation-aware because those are the common counts
  # where a naive plan produces dramatic blank padding on our fixed-width,
  # adaptive-height canvas:
  #   - 2 landscapes  → stacked [1, 1]       (two rows of 1 full-width landscape)
  #   - 2 portraits   → side-by-side [2]     (one row of two half-width portraits)
  #   - 3 landscapes  → hero + pair [1, 2]   (near-square: 1 big on top, 2 below)
  #   - 3 portraits   → row-of-three [3]     (already near-square at adaptive height)
  # For N > 9 we fall back to a square-ish auto grid.
  def row_plan(images)
    n = images.size

    if n == 2
      return [1, 1] if images.all? { |img| img.width > img.height }
      return [2]
    end

    if n == 3
      return [1, 2] if images.all? { |img| img.width > img.height }
      return [3]
    end

    return ROW_PLANS[n] if ROW_PLANS.key?(n)

    cols = Math.sqrt(n).ceil
    rows = (n.to_f / cols).ceil
    per_row = Array.new(rows, cols)
    remainder = (cols * rows) - n
    per_row[-1] -= remainder if remainder.positive?
    per_row
  end

  # Cover-crop the image to exactly fill cell_w x cell_h using libvips'
  # attention-based smart crop (centers on salient features — faces, subjects
  # — instead of the geometric center). Because build_grid picks row heights
  # to match the row's content aspect, most tiles come out essentially
  # uncropped; outliers in a mixed row get a modest smart-crop rather than
  # blind center-cropping or bands of white letterbox.
  #
  # Falls back to :centre if libvips was built without smartcrop (older
  # builds / minimal containers).
  def prepare_tile(image, width, height)
    tile = begin
      image.thumbnail_image(width, height: height, crop: :attention)
    rescue Vips::Error, ArgumentError
      image.thumbnail_image(width, height: height, crop: :centre)
    end
    tile = tile.flatten(background: BACKGROUND) if tile.has_alpha?
    tile.colourspace(:srgb).cast(:uchar)
  end

  def load_image(url)
    data = fetch_bytes(url)
    return nil unless data

    decode_image(data)
  rescue Vips::Error => e
    Sentry.capture_exception(e, extra: { url: sanitize_url(url) })
    nil
  end

  # Decode a JPEG/PNG/etc buffer with libvips, tolerating truncated or partly
  # corrupt scans rather than blowing up the whole collage. A single bad tile
  # in one source image was killing the entire pipeline in production — e.g.
  #   (process:xxx): VIPS-WARNING **: error in tile 0 x 4448
  # which happens when an S3 tmp upload hasn't fully propagated or a proxy cut
  # the body short. With fail_on: :none, libvips returns the decoded portion;
  # with the legacy `fail: false` kwarg for older libvips builds, same idea.
  def decode_image(data)
    Vips::Image.new_from_buffer(data, "", fail_on: :none)
  rescue ArgumentError
    Vips::Image.new_from_buffer(data, "", fail: false)
  end

  # Downloads the URL body using Net::HTTP directly. We avoid open-uri because
  # since Ruby 3.0 it raises "userinfo not supported. [RFC3986]" on any URI
  # with an `@` that parses as userinfo (happens with some legacy Filestack
  # filenames), even if we never intended basic auth.
  #
  # When the server sends a Content-Length header and the received body is
  # shorter, we treat the response as truncated and retry once after a short
  # delay — this is the common S3 read-after-write race when a browser has
  # only just finished PUTting the tmp object. Without this, we hand a
  # half-baked JPEG to libvips and it errors mid-decode.
  def fetch_bytes(url, redirects_left = MAX_REDIRECTS, truncation_retries_left = MAX_TRUNCATION_RETRIES)
    return nil if redirects_left.negative?

    uri = URI.parse(url)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.is_a?(URI::HTTPS)
    http.open_timeout = HTTP_OPEN_TIMEOUT
    http.read_timeout = HTTP_READ_TIMEOUT

    request = Net::HTTP::Get.new(uri.request_uri)
    if uri.userinfo
      user, pass = uri.userinfo.split(":", 2)
      request.basic_auth(user, pass)
    end

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      body = response.body
      expected = response["content-length"]&.to_i
      if expected && expected.positive? && body.to_s.bytesize != expected
        if truncation_retries_left.positive?
          sleep TRUNCATION_RETRY_DELAY
          return fetch_bytes(url, redirects_left, truncation_retries_left - 1)
        end
        Sentry.capture_message(
          "Truncated response in CollageGenerator#fetch_bytes",
          level: :warning,
          extra: { url: sanitize_url(url), expected: expected, received: body.to_s.bytesize }
        )
        return nil
      end
      body
    when Net::HTTPRedirection
      location = response["location"]
      return nil if location.blank?

      fetch_bytes(URI.join(uri, location).to_s, redirects_left - 1, truncation_retries_left)
    end
  rescue StandardError => e
    Sentry.capture_exception(e, extra: { url: sanitize_url(url) })
    nil
  end

  def sanitize_url(url)
    url.to_s.gsub(%r{//[^/@]+@}, "//***@")[0, 200]
  end
end
