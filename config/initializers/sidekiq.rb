# frozen_string_literal: true
Rails.application.config.to_prepare do
  Sidekiq.strict_args!(false)
end

if ENV.key?("SIDEKIQ_CRON_ENABLED")
  require "sidekiq/cron"

  Sidekiq::Cron.configure do |config|
    config.cron_schedule_file = "config/sidekiq_cron_schedule.yml"

    config.cron_poll_interval = 60  # 1 minute in seconds

    # Allow one-off jobs (e.g. daily) to enqueue after a deploy/restart window.
    config.reschedule_grace_period = 600  # 10 minutes in seconds
  end
end
