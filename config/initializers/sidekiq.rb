Sidekiq.configure_client do |config|
  if ENV["REDISCLOUD_URL"]
    config.redis = { url: ENV["REDISCLOUD_URL"], namespace: 'dabbleme' }
  else
    config.redis = { namespace: 'dabbleme' }    
  end
end