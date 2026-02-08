if Rails.env.test?
  # Set CloudflareRails IPs manually to avoid external HTTP requests during tests
  Rails.application.config.after_initialize do
    CloudflareRails::VALID_CLOUDFLARE_CIDRS = ['127.0.0.1/32', '::1/128']
  end
end
