# frozen_string_literal: true

namespace :sidekiq_cron do
  # Mirrors Sidekiq::Cron::ScheduleLoader so ephemeral Redis can be repopulated without
  # restarting Sidekiq (e.g. Railway Cron every 15 minutes).
  desc 'Load schedule from config/sidekiq_cron_schedule.yml into Redis (same as gem boot loader)'
  task reload: :environment do
    require_relative '../dabble/sidekiq_cron_schedule_reloader'

    schedule_file = Dabble::SidekiqCronScheduleReloader.call
    puts "Reloaded sidekiq-cron schedule from #{schedule_file}"
  end
end
