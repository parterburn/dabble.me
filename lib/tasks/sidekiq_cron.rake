# frozen_string_literal: true

namespace :sidekiq_cron do
  # Mirrors Sidekiq::Cron::ScheduleLoader so ephemeral Redis can be repopulated without
  # restarting Sidekiq (e.g. Railway Cron every 10 minutes).
  desc "Load schedule from config/sidekiq_cron_schedule.yml into Redis (same as gem boot loader)"
  task reload: :environment do
    require "sidekiq/cron"

    Sidekiq::Cron.configuration.cron_schedule_file = "config/sidekiq_cron_schedule.yml"
    Sidekiq::Cron::ScheduleLoader.new.load_schedule

    puts "Reloaded sidekiq-cron schedule from #{Sidekiq::Cron.configuration.cron_schedule_file}"
  end
end
