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

  # Brute-force / leaked-token probing: POST /mcp with credentials (Bearer header or access_token query)
  throttle("mcp/auth-attempts/ip", limit: 10, period: 10.minutes) do |req|
    next unless req.path == MCP_PATH && req.post?

    auth = req.env["HTTP_AUTHORIZATION"].to_s
    has_bearer = auth.match?(/\ABearer\s+\S+/i)
    has_query_token = req.GET["access_token"].present?
    next unless has_bearer || has_query_token

    req.ip
  end
end