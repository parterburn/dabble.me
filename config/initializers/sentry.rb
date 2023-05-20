if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.excluded_exceptions = Sentry::Rails::IGNORE_DEFAULT - ["ActionController::BadRequest"]
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]

    config.traces_sample_rate = 1.0
  end
end
