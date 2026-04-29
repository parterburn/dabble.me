# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidekiqCronSchedule do
  before do
    Sidekiq::Cron.configuration.cron_schedule_file = "config/sidekiq_cron_schedule.yml"
  end

  describe ".repair_if_drifted!" do
    it "reloads schedule when Redis is missing cron jobs vs YAML set" do
      allow(Sidekiq::Cron::Job).to receive(:all).and_return([])
      allow(Sidekiq::Cron::Job).to receive(:load_from_hash!)

      described_class.repair_if_drifted!

      expect(Sidekiq::Cron::Job).to have_received(:load_from_hash!).with(
        kind_of(Hash),
        source: "schedule"
      )
    end

    it "does nothing when Redis jobs match YAML keys" do
      path = Rails.root.join("config/sidekiq_cron_schedule.yml")
      yaml_keys = YAML.load_file(path).keys.map(&:to_s)
      jobs = yaml_keys.map { |name| instance_double(Sidekiq::Cron::Job, name: name) }

      allow(Sidekiq::Cron::Job).to receive_messages(all: jobs, load_from_hash!: nil)

      described_class.repair_if_drifted!

      expect(Sidekiq::Cron::Job).not_to have_received(:load_from_hash!)
    end
  end
end
