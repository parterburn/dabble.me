class CaptureBusinessMetricsWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3, queue: :default

  def perform
    # Cron runs at 00:05 UTC, before UserDowngradeExpiredWorker at 00:30.
    # Snapshot yesterday so cash/email cover a full day while users.plan still
    # matches end-of-yesterday (there is no plan history).
    # "Snapshot now" still captures Date.current.
    BusinessMetrics::Capture.call(on: Date.yesterday)
  end
end
