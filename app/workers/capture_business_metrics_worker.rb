class CaptureBusinessMetricsWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3, queue: :default

  def perform
    # Cron runs at 06:00 UTC. Snapshot yesterday so cash and email cover a full day.
    # "Snapshot now" still captures Date.current.
    BusinessMetrics::Capture.call(on: Date.yesterday)
    BusinessMetrics::WeeklyDigest.call if Date.current.monday?
  end
end
