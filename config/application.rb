require File.expand_path('../boot', __FILE__)

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Dabbleme
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    config.time_zone = 'UTC'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    config.autoload_paths << "#{config.root}/lib"

    # Devise
    config.assets.initialize_on_precompile = false

    config.assets.version = '1.0'
    #loads the local_env.yml configuration file
    config.before_configuration do
      env_file = File.join(Rails.root, 'config', 'local_env.yml')
      YAML.load(File.open(env_file)).each do |key, value|
        ENV[key.to_s] = value.to_s
      end if File.exists?(env_file)
    end

    config.assets.precompile += %w(*.png *.jpg *.jpeg *.gif,
                                      "fontawesome-webfont.ttf",
                                     "fontawesome-webfont.eot",
                                     "fontawesome-webfont.svg",
                                     "fontawesome-webfont.woff")



    config.assets.precompile << Proc.new do |path|
          if path =~ /\.(css|js)\z/
            full_path = Rails.application.assets_manifest.find_sources.resolve(path)
            app_assets_path = Rails.root.join('app', 'assets').to_path
            if full_path.starts_with? app_assets_path
              puts "including asset: " + full_path
              true
            else
              puts "excluding asset: " + full_path
              false
            end
          else
            false
          end
        end    

    # Do not swallow errors in after_commit/after_rollback callbacks.
    config.active_record.raise_in_transactional_callbacks = true

    config.exceptions_app = self.routes

    config.middleware.use Rack::Attack
    config.middleware.use Rack::Affiliates
  end
end
