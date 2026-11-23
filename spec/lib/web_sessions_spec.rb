# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebSessions do
  describe '.legacy_sessions_until' do
    it 'uses the grace period when nothing overrides it, as in production' do
      # Production never sets the key, and an unset config.x key reads back as an empty (truthy)
      # OrderedOptions, not nil.
      allow(Rails.application.config).to receive(:x).and_return(Rails::Application::Configuration::Custom.new)

      expect(described_class.legacy_sessions_until).to eq(Time.utc(2026, 12, 24))
      expect { described_class.legacy_sessions_allowed? }.not_to raise_error
    end

    it 'uses a configured time' do
      custom = Rails::Application::Configuration::Custom.new
      custom.legacy_web_sessions_until = Time.utc(2030, 1, 1)
      allow(Rails.application.config).to receive(:x).and_return(custom)

      expect(described_class.legacy_sessions_until).to eq(Time.utc(2030, 1, 1))
    end
  end
end
