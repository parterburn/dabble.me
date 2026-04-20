if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.excluded_exceptions = Sentry::Rails::IGNORE_DEFAULT - ["ActionController::BadRequest"]

    config.environment = Rails.env
    config.sample_rate = 1.0
    config.traces_sample_rate = 1.0
    # Profiling adds call-stack samples to slow transactions (helps find DB vs app bottlenecks).
    # Requires stackprof; 10% in production only.
    config.profiles_sample_rate = Rails.env.production? ? 0.1 : 0.0
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]
    # Intentionally NOT enabling the `:sidekiq_cron` Sentry patch: it would
    # register a monitor for every job in config/sidekiq_cron_schedule.yml,
    # but our Sentry plan only allows one. The single most-important job
    # (SendHourlyEntriesWorker) registers itself via `sentry_monitor_check_ins`.

    # Load stackprof when profiling is enabled so Sentry can attach profiles (avoids WARN).
    require "stackprof" if config.profiles_sample_rate.to_f.positive?

    config.traces_sampler = lambda do |context|
      true
    end
  end
end
