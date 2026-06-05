require "net/http"
require "uri"

# Builds a JPEG collage from a list of image URLs using libvips.
#
# Layout: a "justified rows" gallery (the Flickr / Google Photos approach). A
# per-count "row plan" (see ROW_PLANS + `row_plan`) decides how many tiles land
# in each row, then every tile in a row keeps its EXACT aspect ratio while the
# whole row is scaled to one shared HEIGHT chosen so the row fills the canvas
# width edge-to-edge. Because the height is solved from the photos' real aspect
# ratios — height = available_width / sum(aspect_ratios) — there is no cropping
# and no letterbox padding inside a row: a portrait sitting next to a landscape
# simply renders narrower at the same height instead of being matted with big
# white margins. Rows can differ in height (that's the organic, gap-free look),
# and canvas WIDTH stays fixed at @size while HEIGHT floats with the content.
# For fixed row plans (e.g. eight photos → two rows of four), input order is
# re-sorted by aspect ratio so each row groups similar orientations. White SHIM
# separates tiles and an outer margin mattes the whole canvas. A pathologically
# tall row (e.g. a lone portrait) is capped via MAX_ROW_HEIGHT_RATIO and then
# centered. Duplicate URLs are collapsed.
class CollageGenerator
  MAX_IMAGES = 8
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

  # Upper bound on a justified row's height, as a multiple of the canvas inner
  # width. A row of mostly-portrait photos (small aspect-ratio sum) would
  # otherwise solve to an enormous height; we cap it and center the row instead.
  # We only ever cap DOWN — capping a height up would widen tiles past the
  # canvas and reintroduce cropping, which we never want.
  MAX_ROW_HEIGHT_RATIO = 1.0

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
    images = reorder_images_for_aspect_rows(images, plan)
    inner_w = @size - (2 * SHIM)

    idx = 0
    rows = plan.map do |cols|
      row_imgs = images[idx, cols]
      idx += cols
      build_justified_row(row_imgs, inner_w)
    end

    # Stack rows vertically, centering any capped (narrower-than-canvas) row.
    grid = join_images(rows, :vertical)

    total_h = grid.height + (2 * SHIM)
    grid.embed(SHIM, SHIM, @size, total_h, extend: :background, background: BACKGROUND)
  end

  # One justified row: every tile keeps its true aspect ratio and the row is
  # scaled to a single shared height so its tiles + inter-tile shims fill
  # `inner_w` exactly. Solving the row height this way is what removes both the
  # cropping and the letterbox whitespace of the old per-cell layout.
  #
  #   total_w = Σ(aspect_i · h) + (cols - 1)·SHIM = inner_w
  #   ⇒ h = (inner_w - (cols - 1)·SHIM) / Σ(aspect_i)
  #
  # We only cap the height DOWN (MAX_ROW_HEIGHT_RATIO): capping up would push
  # tile widths past the canvas edge and force a crop. A capped row is narrower
  # than the canvas and gets centered by the outer arrayjoin/embed.
  def build_justified_row(images, inner_w)
    cols = images.size
    avail_w = inner_w - ((cols - 1) * SHIM)
    sum_aspect = images.sum { |img| aspect_ratio(img) }
    sum_aspect = 1.0 if sum_aspect <= 0

    row_h = (avail_w / sum_aspect).round
    row_h = [row_h, (inner_w * MAX_ROW_HEIGHT_RATIO).round].min
    row_h = [row_h, 1].max

    tiles = images.map { |img| scale_to_height(img, row_h) }
    join_images(tiles, :horizontal)
  end

  # Join images edge-to-edge with a white SHIM gutter between them. We use
  # pairwise `join` rather than `arrayjoin` on purpose: arrayjoin sizes every
  # cell to the largest image (re-introducing pillarbox whitespace around a
  # narrow portrait), whereas `join` honors each tile's real width/height.
  # `align: :centre` keeps tiles centered on the cross axis; with `expand` the
  # shorter image is padded with `background` rather than cropped.
  def join_images(images, direction)
    images.reduce do |acc, img|
      acc.join(img, direction, expand: true, shim: SHIM, background: BACKGROUND, align: :centre)
    end
  end

  def aspect_ratio(image)
    return 1.0 if image.width < 1 || image.height < 1

    image.width.to_f / image.height
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

  # Sort by width/height (landscape-heavy → portrait-heavy) then assign
  # consecutive runs to each row in `plan`. That way a [4,4] collage with four
  # of each orientation tends to get one landscape row and one portrait row
  # instead of four mixed cells per row sharing a single compromised height.
  def reorder_images_for_aspect_rows(images, plan)
    return images if images.size <= 1 || plan.blank?

    sorted = images.sort_by { |img| -(img.width.to_f / img.height) }
    out = []
    idx = 0
    plan.each do |cols|
      slice = sorted[idx, cols]
      out.concat(slice) if slice
      idx += cols
    end
    out
  end

  # Resize the image to an exact target height, preserving aspect ratio. No
  # cropping and no padding: width simply follows from the height. Because the
  # scale factor is height/ih, every tile in a row lands on the same integer
  # height, so they line up cleanly when joined across.
  def scale_to_height(image, target_h)
    iw = image.width
    ih = image.height
    raise Vips::Error, 'zero-sized collage source' if iw < 1 || ih < 1

    scaled = image.resize(target_h.to_f / ih)

    # Composite alpha before any joins — libvips requires background vectors to
    # match band count (HEIC often decodes as RGBA; joining with [255,255,255]
    # errors as "linear: vector must have 1 or 4 elements"). CMYK etc. must be
    # sRGB too.
    scaled = scaled.flatten(background: BACKGROUND) if scaled.has_alpha?
    scaled.colourspace(:srgb).cast(:uchar)
  end

  def load_image(url)
    data = fetch_bytes(url)
    return nil unless data

    img = orient_image(decode_image(data))
    # `new_from_buffer` can succeed lazily then fail mid-pipeline (truncated HEIC,
    # seek errors). Materialize while we still know the URL for logging.
    img.copy_memory
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

  # Phone JPEGs/HEIC often store pixels on the side and rely on EXIF orientation.
  # Browsers respect that tag; libvips does not unless we autorot explicitly.
  def orient_image(image)
    image.autorot
  rescue Vips::Error
    image
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
    return nil if url.blank?

    # Malformed strings (e.g. internal sentinels like "mailgun_collage:…" that
    # leaked out of the email processor) should be dropped silently rather than
    # paged to Sentry — they're a caller-contract problem, not a runtime fault
    # to investigate, and the collage degrades gracefully by skipping the tile.
    uri = begin
      URI.parse(url)
    rescue URI::InvalidURIError
      return nil
    end
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
