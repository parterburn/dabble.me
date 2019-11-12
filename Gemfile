source 'https://rubygems.org'

ruby File.read(File.expand_path '../.ruby-version', __FILE__).strip.sub /\-p[0-9]+$/, '' # Read the rbenv version file
gem 'rails', '4.2.11.1'

# Servers
gem 'puma'

# ORM
gem 'pg', '~> 0.21.0'

# users
gem "devise", ">= 4.7.1"
gem 'devise-security'
gem "recaptcha"
gem 'gibbon' # mailchimp connector

gem 'addressable' # better URI checking
gem 'sinatra', '>= 1.3.0', require: nil
gem 'combined_time_select', '~> 1.0.1'

# email parsing
gem 'griddler', '~> 1.5.2'
gem 'griddler-mailgun', '~> 1.1', '>= 1.1.1'

gem 'email_reply_trimmer'
gem 'mailgun_webhooks', '~> 1.0'
gem 'mailgun_rails'

gem 'randomized_field', '~> 0.1.0' # builds user_keys
gem 'summernote-rails', '~> 0.8.2.0'
gem 'rest-client' # RESTClient
gem 'rubyzip', '~> 1.2', '>= 1.2.2'
gem 'zip-zip'
gem 'rack-utf8_sanitizer', '~> 1.5'
gem "loofah", ">= 2.3.1"
gem "chartkick", ">= 3.2.0" # Admin stats
gem 'groupdate' # Admin Stats
gem 'words_counted' # Year in Review

gem 'kaminari' # Pagination

 # Image Uploads
gem 'fog-aws'
gem 'carrierwave', '~> 1.3', '>= 1.3.1'
gem "mini_magick", ">= 4.9.4"
gem 'file_validators'

# Miscellanea
gem 'google-analytics-rails'
gem 'staccato' # server side tracking for Google Analytics
gem 'haml'
gem 'exception_notification-rake', '~> 0.2.1'
gem 'rack-affiliates' # for tracking referrers
gem 'rinku' # linkify urls & emails in entries

# Assets
gem 'autoprefixer-rails'
gem 'coffee-rails', '~> 4.0.0'
gem 'haml_assets'
gem 'i18n-js'
gem 'jquery-rails'
gem 'sass-rails'
gem 'twbs_sass_rails'
gem 'uglifier', '>= 1.3.0'

gem 'le' # logentries
gem "rack-attack" # Request blocking & throttling
gem "cloudflare-rails"
gem "test_after_commit"
gem "sqreen"
gem "stripe"

group :development, :test do
  gem 'byebug', '~> 8.2', '>= 8.2.2'
  gem 'delorean'
  gem 'factory_bot_rails'
  gem 'faker', '~> 1.6', '>= 1.6.1'
  gem "rspec-rails", "~> 3.7.0"
end

group :development do
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'bullet'
  gem 'meta_request'
  gem 'spring'
  gem 'spring-commands-rspec'
  gem 'web-console'
  gem 'derailed'
end

group :test do
  gem 'capybara'
  gem 'database_cleaner'
  gem 'email_spec'
  gem 'rspec'
  gem 'selenium-webdriver'
  gem 'simplecov', require: false
  gem 'webmock', require: false
end

group :staging, :production do
  gem 'rack-timeout'
end

group :production do
  gem 'rails_12factor'
end
