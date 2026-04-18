Turnstile.configure do |config|
  config.enabled = ENV["TURNSTILE_SITE_KEY"].present?
  config.site_key = ENV["TURNSTILE_SITE_KEY"]
  config.secret_key = ENV["TURNSTILE_SECRET_KEY"]
  config.on_failure = ->(verification) {
    # Give us enough context in Sentry to distinguish:
    #   - response_present: false        → browser never produced a token (widget didn't load, submitted too fast, token expired)
    #   - error-codes: [timeout-or-duplicate] → token was stale/replayed
    #   - anything else                  → genuine verify failure
    Sentry.capture_message(
      "Captcha failure during login/registration",
      level: "warning",
      extra: {
        error_codes: Array(verification.result["error-codes"] || verification.result.error_codes),
        response_present: verification.response.present?,
        result: verification.result.to_h
      }
    )
  }
end
