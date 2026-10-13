# frozen_string_literal: true

require 'sidekiq/cron'

module Dabble
  # Loads config/sidekiq_cron_schedule.yml into Redis using the gem's ScheduleLoader.
  # Retries transient Redis connect failures (common on Railway cron cold starts over
  # private networking) so a brief blip does not fail the whole cron run.
  class SidekiqCronScheduleReloader
    TRANSIENT_REDIS_ERRORS = [
      RedisClient::CannotConnectError,
      RedisClient::ConnectionError,
      Errno::ETIMEDOUT,
      Errno::ECONNREFUSED,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH
    ].freeze

    DEFAULT_MAX_ATTEMPTS = 5
    DEFAULT_BASE_DELAY_SECONDS = 1.0

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(
      max_attempts: DEFAULT_MAX_ATTEMPTS,
      base_delay_seconds: DEFAULT_BASE_DELAY_SECONDS,
      schedule_file: 'config/sidekiq_cron_schedule.yml',
      sleeper: ->(seconds) { sleep(seconds) },
      loader: nil
    )
      @max_attempts = max_attempts
      @base_delay_seconds = base_delay_seconds
      @schedule_file = schedule_file
      @sleeper = sleeper
      @loader = loader
    end

    def call
      Sidekiq::Cron.configuration.cron_schedule_file = @schedule_file

      attempt = 0
      begin
        attempt += 1
        (@loader || Sidekiq::Cron::ScheduleLoader.new).load_schedule
        @schedule_file
      rescue *TRANSIENT_REDIS_ERRORS => e
        raise if attempt >= @max_attempts

        delay = @base_delay_seconds * (2**(attempt - 1))
        warn(
          "[sidekiq_cron:reload] Redis unavailable (#{e.class}: #{e.message}); " \
          "retry #{attempt}/#{@max_attempts} in #{delay}s"
        )
        @sleeper.call(delay)
        retry
      end
    end
  end
end
