# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module BusinessMetrics
  class MailgunStats
    Result = Struct.new(:sent, :failed, :opened, :complained, keyword_init: true) do
      def delivery_rate
        attempts = sent + failed
        return nil if attempts.zero?

        sent.to_f / attempts
      end
    end

    class << self
      def fetch(date:)
        new(date: date).fetch
      end

      # Mailgun puts a numeric `total` on accepted/opened/complained, but failures
      # only expose totals under `failed.permanent` and `failed.temporary`.
      def event_total(event)
        return event.to_i if event.is_a?(Numeric)
        return 0 unless event.is_a?(Hash)

        if event["total"].is_a?(Numeric)
          event["total"].to_i
        else
          %w[permanent temporary].sum { |kind| event.dig(kind, "total").to_i }
        end
      end
    end

    def initialize(date:)
      @date = date
    end

    def fetch
      return Result.new(sent: 0, failed: 0, opened: 0, complained: 0) if ENV["MAILGUN_API_KEY"].blank? || domain.blank?

      stats = request_day_stats
      return Result.new(sent: 0, failed: 0, opened: 0, complained: 0) if stats.blank?

      Result.new(
        sent: self.class.event_total(stats["accepted"]),
        failed: self.class.event_total(stats["failed"]),
        opened: self.class.event_total(stats["opened"]),
        complained: self.class.event_total(stats["complained"])
      )
    rescue StandardError => e
      Sentry.capture_exception(e, extra: { mailgun_stats_date: date.to_s })
      Result.new(sent: 0, failed: 0, opened: 0, complained: 0)
    end

    private

    attr_reader :date

    def domain
      ENV["MAIN_DOMAIN"].presence
    end

    def request_day_stats
      start_at = Time.use_zone("UTC") { date.beginning_of_day }
      uri = URI("https://api.mailgun.net/v3/#{domain}/stats/total")
      uri.query = URI.encode_www_form(
        "event" => %w[accepted failed opened complained],
        "resolution" => "day",
        "start" => start_at.to_i,
        "end" => (start_at + 1.day).to_i
      )

      req = Net::HTTP::Get.new(uri)
      req.basic_auth "api", ENV["MAILGUN_API_KEY"]

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(req)
      end
      return unless res.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(res.body)
      payload.fetch("stats", []).find do |stat|
        Date.parse(stat["time"]).to_date == date
      rescue ArgumentError, TypeError
        false
      end
    end
  end
end
