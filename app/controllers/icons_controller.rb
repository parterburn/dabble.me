# frozen_string_literal: true

# Serves the Font Awesome Pro "Slab" icons from our own origin.
#
# The SVGs live in S3 (icons/slab/) because the Pro license doesn't
# allow publishing them in this public repo. icons.scss draws them as CSS
# masks, and browsers fetch mask images with CORS, so loading them straight
# from the CDN needs it to send Access-Control-Allow-Origin. Proxying them
# through dabble.me keeps them same-origin, so CORS never comes into it.
class IconsController < ActionController::Base
  SOURCE_URL = "https://dabble-me.s3.us-east-1.amazonaws.com/icons/slab"
  NAME = /\A[a-z0-9-]+\z/
  MAX_BYTES = 50_000

  def show
    name = params[:name].to_s
    return head(:not_found) unless name.match?(NAME)

    svg = Rails.cache.fetch(["slab-icon", name], expires_in: 1.day, skip_nil: true) { fetch_svg(name) }
    return head(:not_found) unless svg

    request.session_options[:skip] = true # no cookie, so Cloudflare can cache it
    expires_in 1.day, public: true
    # Opened directly, an SVG is a document; don't let it run anything.
    response.headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'"
    send_data svg, type: "image/svg+xml", disposition: "inline"
  end

  private

  def fetch_svg(name)
    response = Faraday.new(request: { open_timeout: 3, timeout: 5 }).get("#{SOURCE_URL}/#{name}.svg")
    body = response.body.to_s
    body if response.status == 200 && body.bytesize <= MAX_BYTES && body.lstrip.start_with?("<svg")
  rescue Faraday::Error
    nil
  end
end
