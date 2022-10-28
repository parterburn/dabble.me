if ENV['LOGTAIL_SKIP_LOGS'].blank? && !Rails.env.test? && ENV['LOGTAIL_KEY'].present?
  http_device = Logtail::LogDevices::HTTP.new(ENV['LOGTAIL_KEY'])
  Rails.logger = Logtail::Logger.new(http_device)
else
  Rails.logger = Logtail::Logger.new(STDOUT)
end
