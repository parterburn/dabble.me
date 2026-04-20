class Rack::Attack
  MCP_PATH = '/mcp'.freeze

  # Throttle high volumes of requests by IP address
  throttle('req/ip', limit: 20, period: 20.seconds) do |req|
    req.ip unless req.path.starts_with?('/assets')
  end

  # Throttle login attempts by IP address
  throttle('logins/ip', limit: 5, period: 20.seconds) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.ip
    end
  end

  # Throttle login attempts by email address
  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.params['email'].presence
    end
  end

  throttle('mcp/ip', limit: 30, period: 1.minute) do |req|
    req.ip if req.path == MCP_PATH && req.post?
  end

  throttle('mcp/auth-failures', limit: 10, period: 10.minutes) do |req|
    req.ip if req.path == MCP_PATH && req.post? && req.env['rack.attack.matched'] == 'mcp/auth_failure'
  end

  track('mcp/auth_failure') do |req|
    req.path == MCP_PATH && req.post?
  end
end