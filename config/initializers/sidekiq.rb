request_thread_count = Integer(ENV["PUMA_THREADS"] || 10)

Sidekiq.configure_server do |config|
  Rails.application.config.after_initialize do
    ActiveRecord::Base.connection_pool.disconnect!

    ActiveSupport.on_load(:active_record) do
      config = Rails.application.config.database_configuration[Rails.env]
      config['reaping_frequency'] = ENV['DATABASE_REAP_FREQ'] || 10 # seconds
      config['pool'] = ENV['WORKER_DB_POOL_SIZE'] || (Sidekiq.options[:concurrency] + 5)
      ActiveRecord::Base.establish_connection(config)

      Rails.logger.info("Connection Pool size for Sidekiq Server is now: #{ActiveRecord::Base.connection.pool.instance_variable_get('@size')}")
    end
  end
end

Sidekiq.configure_client do |config|
  Rails.application.config.after_initialize do
    ActiveRecord::Base.connection_pool.disconnect!

    ActiveSupport.on_load(:active_record) do
      config = Rails.application.config.database_configuration[Rails.env]
      config['reaping_frequency'] = ENV['DATABASE_REAP_FREQ'] || 10 # seconds
      config['pool'] = ENV['WEB_DB_POOL_SIZE'] || request_thread_count
      ActiveRecord::Base.establish_connection(config)

      # DB connection not available during slug compliation on Heroku
      Rails.logger.info("Connection Pool size for web server is now: #{config['pool']}")
    end
  end
end
