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

    # Active Record Encryption for journal text and account secrets (see the
    # `encrypts` calls on Entry, User and Hashtag). Production reads its keys
    # from the environment; EncryptionCheck refuses to start a web or worker
    # process without them. Development and test fall back to fixed keys that
    # protect nothing.
    #
    # Never change hash_digest_class or the keys of an environment that already
    # holds encrypted rows: its data would stop decrypting.
    encryption_setting = lambda do |name|
      ENV["ACTIVE_RECORD_ENCRYPTION_#{name}"].presence ||
        (Rails.env.production? ? nil : "insecure-#{Rails.env}-#{name.downcase}-0123456789abcdef")
    end
    config.active_record.encryption.primary_key = encryption_setting.call("PRIMARY_KEY")
    config.active_record.encryption.deterministic_key = encryption_setting.call("DETERMINISTIC_KEY")
    config.active_record.encryption.key_derivation_salt = encryption_setting.call("KEY_DERIVATION_SALT")
    config.active_record.encryption.hash_digest_class = OpenSSL::Digest::SHA256
    # While rows written before encryption still exist, read them as they are
    # and let lookups on encrypted columns match either form. Set
    # ACTIVE_RECORD_ENCRYPTION_ALLOW_PLAINTEXT=false once `encryption:status`
    # reports no plaintext left; a plaintext row then raises instead of reading.
    allow_plaintext = ENV["ACTIVE_RECORD_ENCRYPTION_ALLOW_PLAINTEXT"] != "false"
    config.active_record.encryption.support_unencrypted_data = allow_plaintext
    config.active_record.encryption.extend_queries = allow_plaintext
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
