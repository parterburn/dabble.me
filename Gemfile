source 'https://rubygems.org'

ruby File.read(File.expand_path '../.ruby-version', __FILE__).strip.sub /\-p[0-9]+$/, '' # Read the rbenv version file
gem 'rails', '~> 6.0', '>= 6.0.4.4'

# Servers
gem 'puma', '~> 4.3'

# ORM
gem 'pg', '~> 1.2', '>= 1.2.3'

# users
gem "devise", ">= 4.7.1"
gem 'devise-security'
gem 'recaptcha', '~> 5.5'
gem 'gibbon' # mailchimp connector

gem 'addressable' # better URI checking
gem 'sinatra', '~> 2.0', '>= 2.0.8.1'
gem 'combined_time_select'
gem 'jekyll-timeago'

gem "rails-html-sanitizer", "~> 1.3.0"

# email parsing
gem 'griddler', '~> 1.5.2'
gem 'griddler-mailgun', '~> 1.1', '>= 1.1.1'

gem 'email_reply_trimmer'

gem 'mailgun_rails'

gem 'randomized_field', '~> 0.1.0' # builds user_keys
gem 'summernote-rails', '~> 0.8.12.0'
gem 'rest-client' # RESTClient
gem 'rubyzip', '~> 1.3'
gem 'zip-zip'
gem 'rack-utf8_sanitizer', '~> 1.7'
gem "loofah", ">= 2.5"
gem "chartkick", ">= 3.4.0"
gem 'groupdate' # Admin Stats
gem 'words_counted' # Year in Review

gem "kaminari", ">= 1.2.1" # pagination

 # Image Uploads
gem 'fog-aws'
gem 'carrierwave', '~> 2.2', '>= 2.2.2'
gem "mini_magick"
gem 'file_validators'
gem 'fastimage'

# Miscellanea
gem 'google-analytics-rails'
gem 'staccato' # server side tracking for Google Analytics
gem 'haml'
gem 'exception_notification-rake'
gem 'rack-affiliates' # for tracking referrers
gem 'rinku' # linkify urls & emails in entries

# Assets
gem 'autoprefixer-rails'
gem 'haml_assets'
gem 'i18n-js'
gem 'jquery-rails'
gem 'sass-rails'
gem 'twbs_sass_rails'
gem 'uglifier'

gem 'le' # logentries
gem "rack-attack" # Request blocking & throttling
gem "cloudflare-rails"
gem "sqreen"
gem "stripe"
gem "reverse_markdown" # text export conversion html->txt

group :development, :test do
  gem 'byebug'
  gem 'delorean'
  gem 'factory_bot_rails'
  gem 'faker'
  gem "rspec-rails"
  gem 'listen'
end

group :development do
  gem 'better_errors', '~> 2.9', '>= 2.9.1'
  gem 'binding_of_caller'
  gem 'bullet'
  gem 'meta_request'
  gem 'spring'
  gem 'spring-commands-rspec'
  gem 'web-console'
  gem 'derailed'
end

group :test do
  gem 'capybara', '~> 3.35', '>= 3.35.3'
  gem 'database_cleaner'
  gem 'email_spec'
  gem 'rspec', '~> 3.10'
  gem 'selenium-webdriver'
  gem 'simplecov', require: false
  gem 'webmock', require: false
end

gem 'rack-timeout'

group :production do
  gem 'rails_12factor'
end
