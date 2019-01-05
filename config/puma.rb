rails_env = ENV['RAILS_ENV'] || 'development'

threads Integer(ENV["PUMA_THREADS_MIN"] || 1), Integer(ENV["PUMA_THREADS"] || 6)

workers Integer(ENV["PUMA_WORKERS"] || 1)
preload_app!

on_worker_boot do
  ActiveRecord::Base.connection_pool.disconnect!

  ActiveSupport.on_load(:active_record) do
    config = ActiveRecord::Base.configurations[Rails.env]
    config['reaping_frequency'] = ENV['DB_REAP_FREQ'] || 10 # seconds
    config['pool']              = ENV['DB_POOL'] || 5
    ActiveRecord::Base.establish_connection(config)
  end
end
