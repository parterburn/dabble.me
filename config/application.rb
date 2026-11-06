require File.expand_path('../boot', __FILE__)

require "rails"

%w(
  active_record/railtie
  action_controller/railtie
  action_view/railtie
  action_mailer/railtie
  active_job/railtie
).each do |railtie|
  begin
    require "#{railtie}"
  rescue LoadError
  end
end

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
# Bundler.require(:default, Rails.env)
Bundler.require(*Rails.groups)

module Dabbleme
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.
    config.load_defaults 8.1

    lib = Rails.root.join('app/lib')
    config.autoload_paths << lib
    config.eager_load_paths << lib

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    config.time_zone = 'UTC'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # config.autoload_paths << "#{config.root}/lib"

    config.active_job.queue_adapter = :sidekiq
    # dotenv-rails loads .env from the before_configuration hook registered
    # when the gem is required. `inherited` runs that hook before this class
    # body, so a mounted .env is visible here. The block is yielded the
    # application class (the hook uses `yield: true`).
    config.before_configuration do |app|
      next unless ENV["REDIS_URL"].present?

      app.config.cache_store = :redis_cache_store, {
        url: ENV["REDIS_URL"],
        ssl_params: {verify_mode: OpenSSL::SSL::VERIFY_NONE},
        expires_in: 8.hours,
        compress: true,
        reconnect_attempts: 1
      }
    end

    config.assets.version = '1.0'

    config.assets.precompile += %w(*.png *.jpg *.jpeg *.gif, *.css, *.svg *.woff *.ttf *.eot *.js)
    config.assets.precompile += %w( i18n.js i18n/translations.js )

    # config.assets.precompile << Proc.new do |path|
    #       if path =~ /\.(css|js)\z/
    #         @assets ||= Rails.application.assets || Sprockets::Railtie.build_environment(Rails.application)
    #         full_path = @assets.resolve(path)
    #         app_assets_path = Rails.root.join('app', 'assets').to_path
    #         if full_path.starts_with? app_assets_path
    #           true
    #         else
    #           false
    #         end
    #       else
    #         false
    #       end
    #     end

    config.exceptions_app = self.routes

    config.action_mailer.delivery_job = "ActionMailer::MailDeliveryJob"

    # Translate malformed-body exceptions raised by Rack's multipart/query parsers
    # into a clean 400 response instead of a 500 that pages us in Sentry for what
    # is unambiguously a client-side fault (truncated uploads, bot probes with a
    # bogus `Content-Type: multipart/form-data; boundary=…`). Rack 3 tags these
    # errors with Rack::BadRequest.
    #
    # Installed twice:
    # - before Rack::MethodOverride, which parses POST bodies ahead of Rails'
    #   exception handling and does not rescue every Rack 3 parser error
    #   (e.g. Rack::Multipart::BoundaryTooLongError);
    # - after the Rails stack, wrapping Rack::Attack and Rack::Affiliates, which
    #   calls `req.params` before routing.
    bad_request_guard = Class.new do
      BAD_REQUEST_ERRORS = [Rack::BadRequest, EOFError].freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      rescue *BAD_REQUEST_ERRORS => e
        [400, { "content-type" => "text/plain" }, ["Bad Request: #{e.class}"]]
      end
    end
    config.middleware.insert_before Rack::MethodOverride, bad_request_guard
    config.middleware.use bad_request_guard
    config.middleware.use Rack::Attack
    config.middleware.use Rack::Affiliates
  end
end
