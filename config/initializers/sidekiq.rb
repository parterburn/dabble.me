Sidekiq.configure_server do |config|
  config.redis = { :url => ENV["REDISTOGO_URL"] }
end