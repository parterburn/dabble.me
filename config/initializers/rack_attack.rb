class Rack::Attack
  if ENV["REJECT_UNPROXIED_REQUESTS"]
    blocklist("block non-proxied requests in production") do |req|
      raw_ip = req.get_header("HTTP_X_FORWARDED_FOR")
      ip_addresses = raw_ip ? raw_ip.strip.split(/[,\s]+/) : []
      proxy_ip = ip_addresses.last

      if !(req.host =~ /heroku/) && req.trusted_proxy?(proxy_ip)
        false
      else
        ::Rails.logger.warn "Rack Attack IP Filtering: blocked request from host #{proxy_ip} to #{req.url}"
        Sentry.capture_message("Rack Attack IP Filtering: blocked request", level: "warning", extra: { host: proxy_ip, request_url: req.url })
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