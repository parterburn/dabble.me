Rails.application.config.to_prepare do
  # see https://devcenter.heroku.com/articles/connecting-heroku-redis#connecting-in-ruby
  Sidekiq.configure_server do |config|
    config.redis = {ssl_params: {verify_mode: OpenSSL::SSL::VERIFY_NONE}}
  end

  Sidekiq.configure_client do |config|
    config.redis = {ssl_params: {verify_mode: OpenSSL::SSL::VERIFY_NONE}}
  end

  Sidekiq.strict_args!(false)
end
