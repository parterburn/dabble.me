class Rack::Attack
  MCP_PATH = '/mcp'.freeze
  OTP_CREDENTIALS_PATH = '/users/otp/credentials'.freeze
  PROBE_BAN_MAXRETRY = 15
  PROBE_BAN_FINDTIME = 5.minutes
  PROBE_BAN_TIME = 1.hour

  # Throttle high volumes of requests by IP address
  throttle('req/ip', limit: 20, period: 20.seconds) do |req|
    req.ip unless req.path.starts_with?('/assets')
  end

  # Throttle OTP second-factor challenge attempts per challenge token and per IP
  throttle('otp/challenge', limit: 5, period: 5.minutes) do |req|
    submitted_otp_challenge(req) if auth_path(req) == OTP_CREDENTIALS_PATH && !req.get?
  end

  throttle('otp/ip', limit: 10, period: 10.minutes) do |req|
    req.ip if auth_path(req) == OTP_CREDENTIALS_PATH && !req.get?
  end

  # Throttle login attempts by IP address
  throttle('logins/ip', limit: 5, period: 20.seconds) do |req|
    req.ip if auth_path(req) == '/users/sign_in' && req.post?
  end

  throttle('logins/ip/hour', limit: 20, period: 1.hour) do |req|
    req.ip if auth_path(req) == '/users/sign_in' && req.post?
  end

  # Devise posts user[email], not a top-level email param.
  throttle('logins/email', limit: 5, period: 20.seconds) do |req|
    submitted_email(req) if auth_path(req) == '/users/sign_in' && req.post?
  end

  throttle('logins/email/hour', limit: 20, period: 1.hour) do |req|
    submitted_email(req) if auth_path(req) == '/users/sign_in' && req.post?
  end

  # Passkey sign-in. The sign-in page asks for a challenge on load (autofill)
  # and again after each attempt, so the GET limit is looser than the POST one.
  throttle('passkeys/challenge/ip', limit: 30, period: 1.minute) do |req|
    req.ip if auth_path(req) == '/passkeys/sessions/new' && req.get?
  end

  throttle('passkeys/sign-in/ip', limit: 10, period: 1.minute) do |req|
    req.ip if auth_path(req) == '/passkeys/sessions' && req.post?
  end

  throttle('passwords/ip', limit: 5, period: 1.hour) do |req|
    req.ip if auth_path(req) == '/users/password' && req.post?
  end

  throttle('passwords/email', limit: 5, period: 1.hour) do |req|
    submitted_email(req) if auth_path(req) == '/users/password' && req.post?
  end

  throttle('signups/ip', limit: 5, period: 1.hour) do |req|
    req.ip if auth_path(req) == '/users' && req.post?
  end

  throttle('signups/email', limit: 5, period: 1.hour) do |req|
    submitted_email(req) if auth_path(req) == '/users' && req.post?
  end

  throttle('checkout/ip', limit: 10, period: 10.minutes) do |req|
    req.ip if auth_path(req) == '/checkout' && req.post?
  end

  throttle('mcp/ip', limit: 30, period: 1.minute) do |req|
    req.ip if auth_path(req) == MCP_PATH && req.post?
  end

  # OAuth dynamic client registration (public); keep tight to limit abuse.
  throttle('oauth/dcr/ip', limit: 5, period: 1.minute) do |req|
    req.ip if auth_path(req) == '/oauth/registrations' && req.post?
  end

  throttle('oauth/dcr/ip/day', limit: 50, period: 1.day) do |req|
    req.ip if auth_path(req) == '/oauth/registrations' && req.post?
  end

  # Brute-force OAuth token attempts against MCP
  throttle('mcp/auth-attempts/ip', limit: 10, period: 10.minutes) do |req|
    next unless auth_path(req) == MCP_PATH && req.post?

    auth = req.env['HTTP_AUTHORIZATION'].to_s
    next unless auth.match?(/\ABearer\s+\S+/i)

    req.ip
  end

  # Counting happens in ProbeResponseCounter, after the status is known.
  # This blocklist only checks whether that counter has already banned the IP.
  blocklist('probe-responses') do |req|
    ip = probe_ip(req)
    next false unless bannable_probe_ip?(ip)

    Allow2Ban.filter(probe_discriminator(ip), probe_ban_options) { false }
  end

  # Rails routes /users/sign_in.json, /users/sign_in/ and //users/sign_in to
  # the same action as /users/sign_in, so compare a normalized path: no
  # repeated or trailing slashes and no format extension.
  def self.auth_path(req)
    path = req.path.squeeze('/')
    path = path.chomp('/') unless path == '/'
    path.sub(/\.[a-z0-9]+\z/i, '')
  end

  # Rack::Request#params only reads query strings and form bodies; Rails also
  # accepts a JSON body, so read the parameters the way the controller will.
  def self.auth_params(req)
    ActionDispatch::Request.new(req.env).params
  rescue StandardError
    req.params
  end

  def self.submitted_email(req)
    params = auth_params(req)
    user_params = params['user']
    email = user_params['email'] if user_params.is_a?(Hash)
    email = params['email'] unless email.is_a?(String)
    return unless email.is_a?(String)

    email.strip.downcase.presence
  end

  def self.submitted_otp_challenge(req)
    params = auth_params(req)
    user_params = params['user']
    challenge = user_params['challenge'] if user_params.is_a?(Hash)
    challenge = params['challenge'] unless challenge.is_a?(String)
    token = challenge.is_a?(String) ? challenge.strip.presence : nil
    token || "missing:#{req.ip}"
  end

  # Prefer CF-Connecting-IP (real browser behind Cloudflare), then Rails'
  # trusted-proxy remote_ip. Plain req.ip alone is unsafe here: traffic is
  # Client → Cloudflare → Railway → app, so REMOTE_ADDR is often a shared
  # hop; banning that IP 403s the whole site.
  def self.probe_ip(req)
    cf = req.get_header('HTTP_CF_CONNECTING_IP').to_s.strip.presence
    return cf if cf

    ActionDispatch::Request.new(req.env).remote_ip.presence || req.ip
  rescue StandardError
    req.ip
  end

  def self.probe_discriminator(ip)
    "probe:#{ip}"
  end

  def self.probe_ban_options
    { maxretry: PROBE_BAN_MAXRETRY, findtime: PROBE_BAN_FINDTIME, bantime: PROBE_BAN_TIME }
  end

  # Never Allow2Ban a private/loopback/link-local address or a Cloudflare edge
  # range — those are shared hops, not individual scanners.
  def self.bannable_probe_ip?(ip)
    return false if ip.blank?

    addr = IPAddr.new(ip)
    return false if addr.loopback? || addr.private? || addr.link_local?
    return false if cloudflare_edge_ip?(addr)

    true
  rescue IPAddr::Error
    false
  end

  def self.cloudflare_edge_ip?(addr)
    return false unless defined?(CloudflareRails::Importer)

    CloudflareRails::Importer.cloudflare_ips.any? { |range| range === addr }
  rescue StandardError
    false
  end

  # Counts 404s from inside the stack, then Allow2Ban blocks the IP on the
  # following request. Assets and the health check are ignored so a missing
  # font or a deploy probe cannot ban a client. 500s are not counted — a
  # deploy/DB blip must not ban real users.
  class ProbeResponseCounter
    PROBE_STATUSES = [404].freeze
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

      ip = Rack::Attack.probe_ip(req)
      return unless Rack::Attack.bannable_probe_ip?(ip)

      Rack::Attack::Allow2Ban.filter(Rack::Attack.probe_discriminator(ip), Rack::Attack.probe_ban_options) { true }
    rescue StandardError
      # The response is already decided. A cache failure must not replace it with a 500.
      nil
    end
  end
end

Rails.application.config.middleware.insert_after Rack::Attack, Rack::Attack::ProbeResponseCounter
