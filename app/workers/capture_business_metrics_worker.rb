class CaptureBusinessMetricsWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3, queue: :default

  def perform
    BusinessMetrics::Capture.call
    BusinessMetrics::WeeklyDigest.call if Date.current.monday?
  end
end
