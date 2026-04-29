# frozen_string_literal: true

require "set"

# Re-applies sidekiq-cron definitions from disk when Redis lost them (e.g. Redis
# restart without persistence). The gem reloads YAML on Sidekiq process boot;
# this covers the case where Redis empties while the Sidekiq process keeps running.
#
# A periodic Sidekiq::Worker cannot self-heal after a full Redis flush (its cron
# definition lives in Redis too), so this uses a background thread in the Sidekiq
# server process instead of cron.
#
# Mirrors Sidekiq::Cron::ScheduleLoader semantics (YAML + ERB, Hash vs Array) but
# resolves paths relative to Rails.root so reload does not depend on process cwd.
class SidekiqCronScheduleSync
  CHECK_INTERVAL_SECONDS = 600

  class << self
    attr_accessor :daemon_thread_for_tests

    def heal_if_needed
      path = absolute_schedule_file_path
      return unless File.file?(path)

      schedule_body = load_schedule_yaml(path)

      expected = expected_cron_job_names(schedule_body)
      return if expected.empty?

      actual = Sidekiq::Cron::Job.all.map(&:name).to_set
      return if actual == expected

      msg = "[SidekiqCronScheduleSync] Cron schedule mismatch (Redis has #{actual.size} jobs," \
              " YAML defines #{expected.size}); reloading from disk"
      Rails.logger.warn(msg)
      Sidekiq.logger.warn(msg)

      apply_schedule_body!(schedule_body)
      nil
    rescue StandardError => e
      Rails.logger.error("[SidekiqCronScheduleSync] #{e.class}: #{e.message}")
      Sidekiq.logger.error("[SidekiqCronScheduleSync] #{e.class}: #{e.message}")
      Sentry.capture_exception(e, extra: { component: 'sidekiq_cron_schedule_sync', phase: 'heal_if_needed' })
      nil
    end

    def start_periodic_daemon(interval: CHECK_INTERVAL_SECONDS)
      self.daemon_thread_for_tests =
        Thread.new do
          Thread.current.abort_on_exception = false
          loop do
            heal_if_needed
            sleep interval
          rescue StandardError => e
            Rails.logger.error("[SidekiqCronScheduleSync] loop error: #{e.class}: #{e.message}")
            Sentry.capture_exception(e, extra: { component: 'sidekiq_cron_schedule_sync', phase: 'daemon_loop' })
          end
        end
    end

    private

    def absolute_schedule_file_path
      rel = Sidekiq::Cron.configuration.cron_schedule_file.to_s
      yml = Rails.root.join(rel)
      return yml.to_s if File.file?(yml)

      yaml = Rails.root.join(rel.sub(/\.yml\z/, ".yaml"))
      return yaml.to_s if File.file?(yaml)

      yml.to_s
    end

    def load_schedule_yaml(path)
      Sidekiq::Cron::Support.load_yaml(ERB.new(File.read(path)).result)
    end

    def expected_cron_job_names(schedule_body)
      case schedule_body
      when Hash
        schedule_body.keys.map(&:to_s).to_set
      when Array
        schedule_body.map { |row| (row["name"] || row[:name]).to_s }.to_set
      else
        Set.new
      end
    end

    def apply_schedule_body!(schedule_body)
      if schedule_body.is_a?(Hash)
        Sidekiq::Cron::Job.load_from_hash!(schedule_body, source: "schedule")
      elsif schedule_body.is_a?(Array)
        Sidekiq::Cron::Job.load_from_array!(schedule_body, source: "schedule")
      else
        raise "Not supported schedule format. Confirm your #{Sidekiq::Cron.configuration.cron_schedule_file}"
      end
    end
  end
end
