source 'https://rubygems.org'

ruby File.read(File.expand_path '../.ruby-version', __FILE__).strip.sub /\-p[0-9]+$/, '' # Read the rbenv version file
gem 'rails', '4.2.10'

# Servers
gem 'puma'

# ORM
gem 'pg'

# users
gem 'devise', '~> 4.2'
gem "recaptcha", require: "recaptcha/rails"
gem 'gibbon' # mailchimp connector

gem 'addressable' # better URI checking
gem 'sinatra', '>= 1.3.0', require: nil
gem 'combined_time_select', '~> 1.0.1'

# email parsing
gem 'griddler', '~> 1.4.0'
gem 'griddler-mailgun'
gem 'email_reply_trimmer'
gem 'mailgun_webhooks', '~> 1.0'
gem 'mailgun_rails'

gem 'randomized_field', '~> 0.1.0' # builds user_keys
gem 'summernote-rails', '~> 0.8.2.0'
gem 'rest-client' # RESTClient
gem 'rubyzip'
gem 'zip-zip'
gem 'rack-utf8_sanitizer'
gem 'chartkick' # Admin Stats
gem 'groupdate' # Admin Stats
gem 'words_counted' # Year in Review

gem 'kaminari' # Pagination

 # Image Uploads
gem 'fog'
gem 'carrierwave', '~> 0.11.2'
gem 'mini_magick'
gem 'file_validators'

# Miscellanea
gem 'google-analytics-rails'
gem "intercom-rails"
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
gem 'newrelic_rpm'
gem 'scout_apm'

group :development, :test do
  gem 'byebug', '~> 8.2', '>= 8.2.2'
  gem 'delorean'
  gem 'factory_girl_rails'
  gem 'faker', '~> 1.6', '>= 1.6.1'
  gem 'rspec-rails'
end

group :development do
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'bullet'
  gem 'meta_request'
  gem 'spring'
  gem 'spring-commands-rspec'
  gem 'web-console'
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
