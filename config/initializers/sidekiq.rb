# frozen_string_literal: true

Rails.application.config.to_prepare do
  Sidekiq.strict_args!(false)
end

Sidekiq.configure_server do |config|
  # Dead set: jobs that exhausted retries. Capped so Redis does not grow without bound.
  # Sidekiq removes oldest dead jobs when over count or age. Option is dead_timeout_in_seconds
  # (not dead_max_age).
  config[:dead_max_jobs] = 10_000
  config[:dead_timeout_in_seconds] = 15_552_000 # 180 days (~6 months)
end

# Gate cron loading via env — keeps cron off in dev/test unless explicitly enabled.
if ENV.key?("SIDEKIQ_CRON_ENABLED")
  require "sidekiq/cron"

  Sidekiq::Cron.configure do |config|
    config.cron_schedule_file = "config/sidekiq_cron_schedule.yml"

    config.cron_poll_interval = 60 # seconds

    # Allow one-off jobs (e.g. daily) to enqueue after a deploy/restart window.
    config.reschedule_grace_period = 600 # seconds
  end

  # Cron metadata lives only in Redis. Managed Redis (e.g. Railway) can restart without
  # durable persistence, wiping cron definitions while Sidekiq keeps running. sidekiq-cron
  # reloads YAML on boot (schedule_loader.rb); we also reload explicitly via Rails.root
  # paths and run a daemon to recover mid-flight Redis flushes — see SidekiqCronSchedule.
  Sidekiq.configure_server do |cfg|
    cfg.on(:startup) do
      SidekiqCronSchedule.load_from_file!
      SidekiqCronSchedule.start_health_daemon
    end
  end
end
