class Rack::Attack
  if ENV["REJECT_UNPROXIED_REQUESTS"].present? && ENV["REJECT_UNPROXIED_REQUESTS"].to_s == "true"
    blocklist("block non-proxied requests in production") do |request|
      raw_ip = request.env["HTTP_X_FORWARDED_FOR"]
      ip_addresses = raw_ip ? raw_ip.strip.split(/[,\s]+/) : []
      proxy_ip = ip_addresses.last

      if !(request.host =~ /heroku/) && ::Rails.application.config.cloudflare.ips.any?{ |proxy| proxy === proxy_ip }
        false
      else
        ::Rails.logger.warn "Rack Attack IP Filtering: blocked request from #{proxy_ip} to #{request.url} // HOST: #{request.host}"
        true
      end
    end
  end

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
end