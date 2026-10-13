# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../lib/dabble/sidekiq_cron_schedule_reloader'

RSpec.describe Dabble::SidekiqCronScheduleReloader do
  let(:loader) { instance_double(Sidekiq::Cron::ScheduleLoader, load_schedule: true) }
  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }

  def reloader(**overrides)
    described_class.new(
      loader: loader,
      sleeper: sleeper,
      base_delay_seconds: 1.0,
      max_attempts: 4,
      **overrides
    )
  end

  it 'loads the schedule on the first attempt' do
    expect(reloader.call).to eq('config/sidekiq_cron_schedule.yml')
    expect(loader).to have_received(:load_schedule).once
    expect(sleeps).to be_empty
  end

  it 'retries transient Redis connect errors with exponential backoff' do
    calls = 0
    allow(loader).to receive(:load_schedule) do
      calls += 1
      raise RedisClient::CannotConnectError, 'Connection timed out - user specified timeout: 3s' if calls < 3
    end

    expect {
      reloader.call
    }.to output(/Redis unavailable.*retry 1\/4.*retry 2\/4/m).to_stderr

    expect(calls).to eq(3)
    expect(sleeps).to eq([1.0, 2.0])
  end

  it 'raises after exhausting retries' do
    allow(loader).to receive(:load_schedule)
      .and_raise(RedisClient::CannotConnectError, 'Connection timed out')

    expect {
      expect { reloader(max_attempts: 2).call }.to raise_error(RedisClient::CannotConnectError)
    }.to output(/retry 1\/2/).to_stderr

    expect(loader).to have_received(:load_schedule).twice
    expect(sleeps).to eq([1.0])
  end
end
