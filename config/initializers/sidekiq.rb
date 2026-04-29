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

  # sidekiq-cron already reloads YAML on Sidekiq boot (schedule_loader.rb). Redis
  # plugins (e.g. Railway) may restart Redis without persistence, wiping cron
  # definitions while the Sidekiq process keeps running; nothing re-enqueues then.
  # A periodic Sidekiq-cron entry cannot heal a full wipe (it's stored in Redis too),
  # so we re-assert the YAML schedule from disk on an interval inside the Sidekiq process.
  Sidekiq.configure_server do |config|
    config.on(:startup) do
      SidekiqCronScheduleSync.start_periodic_daemon
    end
  end
end
