Sidekiq.configure_client do |config|
  config.redis = { :size => 2, :namespace => 'dabbleme' }
end