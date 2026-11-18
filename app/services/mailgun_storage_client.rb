# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Reads a Mailgun stored message or attachment. The API key is sent only as an
# Authorization header to api.mailgun.net, never in the URL.
class MailgunStorageClient
  class DownloadError < StandardError; end

  API_HOST = "api.mailgun.net"
  MAX_REDIRECTS = 3

  Response = Struct.new(:body, :status, :content_type, :error, keyword_init: true) do
    def ok?
      error.nil? && status.to_i.between?(200, 299) && !body.nil?
    end
  end

  def self.get(url, redirects_left: MAX_REDIRECTS)
    new.get(url, redirects_left: redirects_left)
  end

  def get(url, redirects_left: MAX_REDIRECTS)
    return failure("Mailgun URL is not on #{API_HOST}") if redirects_left.negative?

    uri = api_uri(url)
    return failure("Mailgun URL is not on #{API_HOST}") unless uri

    addresses = SafeRemoteFetch.public_addresses(API_HOST)
    return failure("Mailgun API host did not resolve to a public address") if addresses.empty?

    response = request(uri, addresses.first)
    case response
    when Net::HTTPRedirection
      follow_redirect(response, redirects_left)
    when Net::HTTPSuccess
      Response.new(
        body: response.body.to_s,
        status: response.code.to_i,
        content_type: response["content-type"].to_s.split(";").first.to_s.strip
      )
    else
      Response.new(status: response.code.to_i, error: "Mailgun storage returned #{response.code}")
    end
  rescue DownloadError => e
    failure(e.message)
  rescue StandardError => e
    failure(scrub(e.message))
  end

  # Mailgun hands back storage.mailgun.net (and regional storage hosts). The
  # key is only presented to the fixed API host, using that path.
  def api_uri(url)
    uri = URI.parse(url.to_s)
    return nil unless uri.is_a?(URI::HTTPS)
    return nil if uri.userinfo.present?
    return nil unless mailgun_host?(uri.host)

    path = uri.path.to_s
    path = "/" if path.empty?
    URI::HTTPS.build(host: API_HOST, path: path, query: uri.query)
  rescue URI::InvalidURIError
    nil
  end

  private

  def request(uri, ip)
    Net::HTTP.start(
      API_HOST,
      443,
      use_ssl: true,
      ipaddr: ip,
      open_timeout: 120,
      read_timeout: 120
    ) do |http|
      http_request = Net::HTTP::Get.new(uri.request_uri.presence || "/")
      http_request.basic_auth("api", api_key)
      http.request(http_request)
    end
  end

  def follow_redirect(response, redirects_left)
    location = response["location"].to_s
    return failure("Mailgun redirect was missing") if location.blank?
    return failure("Mailgun URL is not on #{API_HOST}") unless api_uri(location)

    get(location, redirects_left: redirects_left - 1)
  end

  def mailgun_host?(host)
    host = host.to_s.downcase
    host == API_HOST || host.end_with?(".mailgun.net")
  end

  def api_key
    ENV["MAILGUN_API_KEY"].to_s
  end

  def scrub(text)
    cleaned = text.to_s.dup
    key = api_key
    cleaned.gsub!(key, "[FILTERED]") if key.present?
    cleaned.gsub!(%r{//[^/\s@:]+:[^/\s@]+@}i, "//[FILTERED]@")
    cleaned.gsub!(%r{//[^/\s@]+@}i, "//[FILTERED]@")
    cleaned
  end

  def failure(message)
    Response.new(error: scrub(message))
  end
end
