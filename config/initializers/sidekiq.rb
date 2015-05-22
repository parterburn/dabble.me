Sidekiq.configure_client do |config|
  config.redis = { namespace: 'dabbleme' }
end