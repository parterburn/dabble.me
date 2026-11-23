# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebSessions do
  describe '.legacy_sessions_until' do
    around do |example|
      original = Rails.application.config.x.legacy_web_sessions_until
      example.run
    ensure
      Rails.application.config.x.legacy_web_sessions_until = original
    end

    it 'uses the grace period when nothing overrides it, as in production' do
      # An unset config.x key reads back as an empty (truthy) OrderedOptions, not nil.
      Rails.application.config.x.delete(:legacy_web_sessions_until)

      expect(described_class.legacy_sessions_until).to eq(Time.utc(2026, 12, 24))
      expect { described_class.legacy_sessions_allowed? }.not_to raise_error
    end

    it 'uses a configured time' do
      Rails.application.config.x.legacy_web_sessions_until = Time.utc(2030, 1, 1)

      expect(described_class.legacy_sessions_until).to eq(Time.utc(2030, 1, 1))
    end
  end
end
