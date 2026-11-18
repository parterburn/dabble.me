# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "resolv"
require "uri"

# Downloads an http(s) URL only after the host resolves to public addresses.
# Every redirect is checked the same way, and the TCP connection is pinned to
# an address from that lookup so a later DNS answer cannot retarget it.
class SafeRemoteFetch
  Result = Struct.new(:body, :content_type, :content_length, :final_url, :error, keyword_init: true) do
    def ok?
      error.nil?
    end
  end

  MAX_REDIRECTS = 5
  MAX_BYTES = 20.megabytes
  OPEN_TIMEOUT = 15
  READ_TIMEOUT = 60

  IPV4_BLOCKED_RANGES = [
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("100.64.0.0/10"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.0.0.0/24"),
    IPAddr.new("192.0.2.0/24"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("198.18.0.0/15"),
    IPAddr.new("198.51.100.0/24"),
    IPAddr.new("203.0.113.0/24"),
    IPAddr.new("224.0.0.0/4"),
    IPAddr.new("240.0.0.0/4")
  ].freeze

  IPV6_BLOCKED_RANGES = [
    IPAddr.new("::/128"),
    IPAddr.new("::1/128"),
    IPAddr.new("::ffff:0:0/96"),
    IPAddr.new("64:ff9b::/96"),
    IPAddr.new("100::/64"),
    IPAddr.new("2001:db8::/32"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10"),
    IPAddr.new("ff00::/8")
  ].freeze

  def self.fetch(url, https_only: false, max_bytes: MAX_BYTES, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, redirects_left: MAX_REDIRECTS)
    new(
      https_only: https_only,
      max_bytes: max_bytes,
      open_timeout: open_timeout,
      read_timeout: read_timeout
    ).fetch(url, redirects_left)
  end

  def self.public_host?(url)
    uri = parse_http_uri(url)
    return false unless uri
    return false if uri.userinfo.present?

    public_addresses(uri.host).any?
  end

  def self.parse_http_uri(url)
    uri = url.is_a?(URI::Generic) ? url : URI.parse(url.to_s.strip)
    return nil unless uri.is_a?(URI::HTTP)
    return nil if uri.host.blank?

    uri
  rescue URI::InvalidURIError
    nil
  end

  def self.public_addresses(host)
    _status, ips = lookup(host)
    ips
  end

  def self.lookup(host)
    host = normalize_host(host)
    return [:private_host, []] if host.blank? || blocked_hostname?(host) || spoofed_ipv4?(host)

    ips = ip_literal?(host) ? [host] : Resolv.getaddresses(host)
    return [:unresolved_host, []] if ips.empty?
    return [:private_host, []] unless ips.all? { |ip| public_ip?(ip) }

    [:ok, ips]
  rescue Resolv::ResolvError, IPAddr::InvalidAddressError
    [:unresolved_host, []]
  end

  def self.public_ip?(ip)
    addr = IPAddr.new(ip.to_s)
    return false if addr.loopback? || addr.private? || addr.link_local?

    if addr.ipv4?
      IPV4_BLOCKED_RANGES.none? { |range| range.include?(addr) }
    elsif addr.ipv6?
      IPV6_BLOCKED_RANGES.none? { |range| range.include?(addr) }
    else
      false
    end
  rescue IPAddr::InvalidAddressError
    false
  end

  def self.blocked_hostname?(host)
    host = normalize_host(host)
    return true if host.blank?
    return true if host == "localhost" || host.end_with?(".localhost")
    return true if host.end_with?(".local")
    return true if host == "metadata.google.internal"

    false
  end

  def self.normalize_host(host)
    host.to_s.downcase.delete_suffix(".").strip
  end

  def self.ip_literal?(host)
    IPAddr.new(host)
    true
  rescue IPAddr::InvalidAddressError
    false
  end

  # "0177.0.0.1" is loopback on some clients and a public name on others.
  def self.spoofed_ipv4?(host)
    return false unless host.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/)

    host.split(".").any? { |octet| octet.length > 1 && octet.start_with?("0") }
  end

  def initialize(https_only:, max_bytes:, open_timeout:, read_timeout:)
    @https_only = https_only
    @max_bytes = max_bytes
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  def fetch(url, redirects_left)
    return failure(:too_many_redirects) if redirects_left.negative?

    uri = self.class.parse_http_uri(url)
    return failure(:invalid_url) unless uri
    return failure(:credentials) if uri.userinfo.present?
    return failure(:https_required) if @https_only && !uri.is_a?(URI::HTTPS)

    status, addresses = self.class.lookup(uri.host)
    return failure(status) if addresses.empty?

    response = request(uri, addresses.first)
    case response
    when Net::HTTPRedirection
      follow_redirect(uri, response, redirects_left)
    when Net::HTTPSuccess
      success(uri, response)
    else
      failure(:http_error)
    end
  rescue StandardError
    failure(:http_error)
  end

  private

  def request(uri, ip)
    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.is_a?(URI::HTTPS),
      ipaddr: ip,
      open_timeout: @open_timeout,
      read_timeout: @read_timeout
    ) do |http|
      http.request(Net::HTTP::Get.new(request_path(uri)))
    end
  end

  def request_path(uri)
    path = uri.request_uri.to_s
    path = "/" if path.empty? || !path.start_with?("/")
    path
  end

  def follow_redirect(uri, response, redirects_left)
    location = response["location"].to_s
    return failure(:invalid_redirect) if location.blank?

    fetch(URI.join(uri.to_s, location).to_s, redirects_left - 1)
  rescue URI::InvalidURIError
    failure(:invalid_redirect)
  end

  def success(uri, response)
    declared = response["content-length"]&.to_i
    return failure(:too_large) if declared && declared > @max_bytes

    body = response.body.to_s
    return failure(:too_large) if body.bytesize > @max_bytes

    Result.new(
      body: body,
      content_type: response["content-type"].to_s.split(";").first.to_s.strip,
      content_length: declared,
      final_url: uri.to_s
    )
  end

  def failure(error)
    Result.new(error: error)
  end
end
