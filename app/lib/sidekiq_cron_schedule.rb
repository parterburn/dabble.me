# frozen_string_literal: true

require "set"

# Loads and repairs Sidekiq-Cron definitions from config/sidekiq_cron_schedule.yml (or path
# from Sidekiq::Cron.configuration), resolved under Rails.root.
#
# Why this exists:
#   Cron metadata lives only in Redis. If Redis restarts without persistence
#   (common on managed Redis plugins), jobs disappear while Sidekiq keeps running
#   and nothing re-enqueues them. A periodic Sidekiq-Cron entry cannot self-heal
#   a full wipe (the entry itself lives in Redis), so we run a background thread
#   inside the Sidekiq server process that re-asserts the YAML schedule on an interval.
#
# Limitations:
#   With multiple Sidekiq processes, all of them run this daemon and may race on reload.
#   The operation is idempotent so this is benign in practice. If it ever matters, gate the
#   daemon behind a single-process env flag.

module SidekiqCronSchedule
  CHECK_INTERVAL_SECONDS = 600

  class << self
    attr_accessor :health_daemon_thread_for_tests

    def load_from_file!
      schedule = read_schedule
      return unless schedule

      apply_schedule_body!(schedule)
      log(
        "Loaded #{schedule.size} cron jobs from #{schedule_path.basename}",
        level: :info
      )
    end

    def repair_if_drifted!
      schedule_body = read_schedule
      return unless schedule_body

      expected = expected_cron_job_names(schedule_body)
      return if expected.empty?

      actual_names = Sidekiq::Cron::Job.all.map(&:name).to_set
      return if actual_names == expected

      apply_schedule_body!(schedule_body)

      log(
        "Schedule drift detected — reloaded cron jobs from disk " \
          "(Redis had #{actual_names.size}, YAML defines #{expected.size}). " \
          "Redis may have restarted or schedule changed.",
        level: :warn
      )
    end

    def start_health_daemon(interval: CHECK_INTERVAL_SECONDS)
      self.health_daemon_thread_for_tests =
        Thread.new do
          Thread.current.abort_on_exception = false
          Thread.current.name = "sidekiq-cron-schedule-health" if Thread.current.respond_to?(:name=)

          loop do
            sleep interval
            repair_if_drifted!
          rescue StandardError => e
            Rails.logger.error("[SidekiqCronSchedule] daemon error: #{e.class}: #{e.message}")
            Sidekiq.logger&.error("[SidekiqCronSchedule] daemon error: #{e.class}: #{e.message}")
            Sentry.capture_exception(
              e,
              extra: { component: 'sidekiq_cron_schedule', phase: 'health_daemon_loop' }
            )
          end
        end
    end

    private

    def schedule_path
      rel = Sidekiq::Cron.configuration.cron_schedule_file.to_s
      yml = Rails.root.join(rel)
      return yml if yml.file?

      yaml = Rails.root.join(rel.sub(/\.yml\z/, ".yaml"))
      return yaml if yaml.file?

      yml
    end

    def read_schedule
      path = schedule_path
      return nil unless path.file?

      Sidekiq::Cron::Support.load_yaml(ERB.new(path.read).result)
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
        raise(
          "Not supported schedule format. Confirm your #{Sidekiq::Cron.configuration.cron_schedule_file}"
        )
      end
    end

    def log(message, level: :info)
      full = "[SidekiqCronSchedule] #{message}"
      Rails.logger.public_send(level, full)
      Sidekiq.logger&.public_send(level, full)
    end
  end
end
