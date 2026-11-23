# frozen_string_literal: true

module Mcp
  # The parts of the MCP authorization spec (2025-06-18 and later) that Doorkeeper leaves to us.
  #
  # - Resource indicators (RFC 8707): a client names the server it wants a token for in
  #   `resource`. Doorkeeper ignores the parameter, so a token asked for some other server would
  #   be issued silently. We serve one resource, /mcp, and answer anything else with
  #   invalid_target. A request without `resource` (the iOS app, older clients) still works.
  # - Exact redirect URIs (OAuth 2.1, RFC 9700 §4.1.3): Doorkeeper drops the query before it
  #   compares, so https://client/cb?next=x matched a client registered as https://client/cb.
  #   Only the port of a loopback redirect may differ (RFC 8252 §7.3).
  module OauthRules
    RESOURCE_PATH = '/mcp'
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze

    module_function

    def allowed_resource?(resource, base_url)
      values = Array(resource)
      return true if values.empty? || values.all?(&:blank?)

      values.all? { |value| acceptable_resources(base_url).include?(normalize_resource(value)) }
    end

    def exact_redirect_uri?(requested, registered)
      requested = requested.to_s
      registered.to_s.split.any? do |candidate|
        candidate == requested || loopback_port_variant?(requested, candidate)
      end
    end

    # The MCP endpoint and the bare origin. Clients send either, depending on whether they take
    # the resource from the protected resource metadata or from the server URL the user typed.
    def acceptable_resources(base_url)
      base = base_url.to_s.chomp('/')
      [base, "#{base}#{RESOURCE_PATH}"]
    end

    def normalize_resource(value)
      uri = URI.parse(value.to_s.strip)
      return nil if uri.fragment.present? || uri.query.present? || uri.host.blank?

      path = uri.path.to_s.chomp('/')
      port = uri.port == uri.default_port ? '' : ":#{uri.port}"
      "#{uri.scheme.to_s.downcase}://#{uri.host.downcase}#{port}#{path}"
    rescue URI::InvalidURIError
      nil
    end

    def loopback_port_variant?(requested, registered)
      a = URI.parse(requested)
      b = URI.parse(registered)
      return false unless loopback?(a) && loopback?(b)

      a.port = nil
      b.port = nil
      a.to_s == b.to_s
    rescue URI::InvalidURIError
      false
    end

    def loopback?(uri)
      uri.scheme == 'http' && LOOPBACK_HOSTS.include?(uri.host.to_s.downcase)
    end
  end
end
