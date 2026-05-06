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

# sidekiq-cron: https://github.com/sidekiq-cron/sidekiq-cron
# ScheduleLoader (bundled with the gem) runs on Sidekiq process startup and loads the YAML.
# Gate with SIDEKIQ_CRON_ENABLED so dev/test Sidekiq processes skip cron unless you opt in.
if ENV.key?("SIDEKIQ_CRON_ENABLED")
  require "sidekiq/cron"

  Sidekiq::Cron.configure do |config|
    config.cron_schedule_file = "config/sidekiq_cron_schedule.yml"
    config.cron_poll_interval = 60
    config.reschedule_grace_period = 600 # seconds — catch-up after deploy/restart
  end
end
