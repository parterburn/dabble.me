# frozen_string_literal: true

require "net/http"

# Checks the token Cloudflare Access adds to every request it lets through
# (Cf-Access-Jwt-Assertion), so admin routes stay closed even to a request
# that reaches the app without passing Cloudflare, or by a path an Access
# rule doesn't cover.
#
# Off until both variables are set:
#   CLOUDFLARE_ACCESS_TEAM_DOMAIN  e.g. "dabble.cloudflareaccess.com"
#   CLOUDFLARE_ACCESS_AUD          the Access application's "Application Audience (AUD) Tag"
#
# Once on, a missing, expired or forged token, or one for another Access
# application, is refused. If Cloudflare's signing keys can't be fetched, the
# request is refused too.
module CloudflareAccess
  HEADER = "HTTP_CF_ACCESS_JWT_ASSERTION"
  KEYS_TTL = 1.hour
  # A token signed with a key we don't have triggers at most one refetch per interval.
  REFETCH_INTERVAL = 5.minutes
  HTTP_TIMEOUT = 5

  @mutex = Mutex.new
  @keys = nil
  @keys_fetched_at = nil

  class << self
    def enabled?
      team_domain.present? && audience.present?
    end

    def team_domain
      ENV["CLOUDFLARE_ACCESS_TEAM_DOMAIN"].to_s.strip.sub(%r{\Ahttps?://}, "").chomp("/").presence
    end

    def audience
      ENV["CLOUDFLARE_ACCESS_AUD"].to_s.strip.presence
    end

    # Routing constraint: `constraints(CloudflareAccess) { ... }`.
    def matches?(request)
      allowed?(request)
    end

    def allowed?(request)
      return true unless enabled?

      valid_token?(request.get_header(HEADER))
    end

    def valid_token?(token)
      return false if token.blank?

      JWT.decode(
        token, nil, true,
        algorithms: ["RS256"],
        jwks: method(:jwks),
        aud: audience, verify_aud: true,
        iss: "https://#{team_domain}", verify_iss: true,
        required_claims: %w[exp aud iss]
      )
      true
    rescue JWT::DecodeError, KeyError, JSON::ParserError, SystemCallError, Timeout::Error, Net::HTTPError, OpenSSL::SSL::SSLError, SocketError
      false
    end

    def reset_keys!
      @mutex.synchronize do
        @keys = nil
        @keys_fetched_at = nil
      end
    end

    private

    # JWT calls this with { kid_not_found: true } when no cached key matches.
    def jwks(options = {})
      @mutex.synchronize do
        stale = @keys.nil? || @keys_fetched_at < KEYS_TTL.ago
        retry_unknown_kid = options[:kid_not_found] && @keys_fetched_at && @keys_fetched_at < REFETCH_INTERVAL.ago
        if stale || retry_unknown_kid
          @keys = fetch_keys
          @keys_fetched_at = Time.current
        end
        @keys
      end
    end

    def fetch_keys
      uri = URI("https://#{team_domain}/cdn-cgi/access/certs")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
        http.get(uri.request_uri)
      end
      raise Net::HTTPError.new("Cloudflare Access certs: HTTP #{response.code}", response) unless response.is_a?(Net::HTTPSuccess)

      JWT::JWK::Set.new(JSON.parse(response.body))
    end
  end
end
