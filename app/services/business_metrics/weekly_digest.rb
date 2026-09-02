# frozen_string_literal: true

module BusinessMetrics
  class WeeklyDigest
    class << self
      def call(now: Time.current)
        new(now: now).call
      end
    end

    def initialize(now: Time.current)
      @now = now
      @dashboard = Admin::Dashboard.new(now: now)
    end

    def call
      return if recipients.empty?

      FounderMailer.weekly_digest(recipients, dashboard).deliver_now
    end

    private

    attr_reader :now, :dashboard

    def recipients
      emails = User.not_deleted.where(admin: true).pluck(:email)
      extra = ENV["FOUNDER_DIGEST_EMAIL"].presence
      emails << extra if extra
      emails.map { |email| email.to_s.downcase.strip }.reject(&:blank?).uniq
    end
  end
end
