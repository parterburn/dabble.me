class Rack::Attack
  MCP_PATH = '/mcp'.freeze
  PROBE_BAN_MAXRETRY = 15
  PROBE_BAN_FINDTIME = 5.minutes
  PROBE_BAN_TIME = 1.hour

  # Throttle high volumes of requests by IP address
  throttle('req/ip', limit: 20, period: 20.seconds) do |req|
    req.ip unless req.path.starts_with?('/assets')
  end

  # Throttle login attempts by IP address
  throttle('logins/ip', limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == '/users/sign_in' && req.post?
  end

  throttle('logins/ip/hour', limit: 20, period: 1.hour) do |req|
    req.ip if req.path == '/users/sign_in' && req.post?
  end

  # Devise posts user[email], not a top-level email param.
  throttle('logins/email', limit: 5, period: 20.seconds) do |req|
    submitted_email(req) if req.path == '/users/sign_in' && req.post?
  end

  throttle('logins/email/hour', limit: 20, period: 1.hour) do |req|
    submitted_email(req) if req.path == '/users/sign_in' && req.post?
  end

  throttle('passwords/ip', limit: 5, period: 1.hour) do |req|
    req.ip if req.path == '/users/password' && req.post?
  end

  throttle('passwords/email', limit: 5, period: 1.hour) do |req|
    submitted_email(req) if req.path == '/users/password' && req.post?
  end

  throttle('signups/ip', limit: 5, period: 1.hour) do |req|
    req.ip if req.path == '/users' && req.post?
  end

  throttle('signups/email', limit: 5, period: 1.hour) do |req|
    submitted_email(req) if req.path == '/users' && req.post?
  end

  throttle('checkout/ip', limit: 10, period: 10.minutes) do |req|
    req.ip if req.path == '/checkout' && req.post?
  end

  throttle('mcp/ip', limit: 30, period: 1.minute) do |req|
    req.ip if req.path == MCP_PATH && req.post?
  end

  # OAuth dynamic client registration (public); keep tight to limit abuse.
  throttle('oauth/dcr/ip', limit: 5, period: 1.minute) do |req|
    req.ip if req.path == '/oauth/registrations' && req.post?
  end

  throttle('oauth/dcr/ip/day', limit: 50, period: 1.day) do |req|
    req.ip if req.path == '/oauth/registrations' && req.post?
  end

  # Brute-force OAuth token attempts against MCP
  throttle('mcp/auth-attempts/ip', limit: 10, period: 10.minutes) do |req|
    next unless req.path == MCP_PATH && req.post?

    auth = req.env['HTTP_AUTHORIZATION'].to_s
    next unless auth.match?(/\ABearer\s+\S+/i)

    req.ip
  end

  # Counting happens in ProbeResponseCounter, after the status is known.
  # This blocklist only checks whether that counter has already banned the IP.
  blocklist('probe-responses') do |req|
    Allow2Ban.filter(probe_discriminator(req.ip), probe_ban_options) { false }
  end

  def self.submitted_email(req)
    user_params = req.params['user']
    email = user_params['email'] if user_params.is_a?(Hash)
    email = req.params['email'] unless email.is_a?(String)
    return unless email.is_a?(String)

    email.strip.downcase.presence
  end

  def self.probe_discriminator(ip)
    "probe:#{ip}"
  end

  def self.probe_ban_options
    { maxretry: PROBE_BAN_MAXRETRY, findtime: PROBE_BAN_FINDTIME, bantime: PROBE_BAN_TIME }
  end

  # Counts 404s and 500s from inside the stack, then Allow2Ban blocks the IP
  # on the following request. Assets and the health check are ignored so a
  # missing font or a deploy probe cannot ban a client.
  class ProbeResponseCounter
    PROBE_STATUSES = [404, 500].freeze
    SKIP_PREFIXES = ['/assets', '/health_check'].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      record_probe(env, status)
      [status, headers, body]
    end

    private

    def record_probe(env, status)
      return unless PROBE_STATUSES.include?(status.to_i)

      req = Rack::Request.new(env)
      return if SKIP_PREFIXES.any? { |prefix| req.path.start_with?(prefix) }

      Rack::Attack::Allow2Ban.filter(Rack::Attack.probe_discriminator(req.ip), Rack::Attack.probe_ban_options) { true }
    rescue StandardError
      # The response is already decided. A cache failure must not replace it with a 500.
      nil
    end
  end
end

Rails.application.config.middleware.insert_after Rack::Attack, Rack::Attack::ProbeResponseCounter
