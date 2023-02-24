Turnstile.configure do |config|
  config.enabled = ENV["TURNSTILE_SITE_KEY"].present?
  config.site_key = ENV["TURNSTILE_SITE_KEY"]
  config.secret_key = ENV["TURNSTILE_SECRET_KEY"]
  config.on_failure = ->(verification) {
    Sentry.capture_message("Captcha failure during registration", level: "warning", extra: { result: verification.result })
  }
end
