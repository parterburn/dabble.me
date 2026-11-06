class FounderWeeklyDigestWorker
  include Sidekiq::Job

  sidekiq_options retry: 3, queue: :default

  def perform
    BusinessMetrics::WeeklyDigest.call
  end
end
