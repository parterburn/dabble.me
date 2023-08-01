source 'https://rubygems.org'

ruby File.read(File.expand_path '../.ruby-version', __FILE__).strip.sub /\-p[0-9]+$/, '' # Read the rbenv version file
gem 'rails', '~> 6.0', '>= 6.0.6.1'

gem 'puma', '~> 6'
gem 'pg', '~> 1.5', '>= 1.2.3'
# gem 'barnes'

# users
gem "devise", ">= 4.7.1"
gem 'devise-security'
gem "turnstile-captcha", require: "turnstile"
gem 'gibbon' # mailchimp connector

gem 'addressable' # better URI checking
# gem 'sinatra', '~> 2.0', '>= 2.0.8.1'
gem 'combined_time_select'
gem 'jekyll-timeago'

gem "rails-html-sanitizer", "~> 1.6"

# email parsing
gem 'email_reply_trimmer'
gem 'griddler-mailgun', '~> 1.1', '>= 1.1.1'
gem 'griddler', '~> 1.5.2'
gem "charlock_holmes", "~> 0.7.7" # text encoding detection for email parsing

gem 'mailgun_rails'
gem "ruby-openai"

gem 'groupdate' # Admin Stats
gem 'rack-utf8_sanitizer', '~> 1.8'
gem 'randomized_field', '~> 1.0' # builds user_keys
gem 'rest-client' # RESTClient
gem 'rubyzip', '~> 2'
gem 'summernote-rails', '~> 0.8.20.0', git: "https://github.com/parterburn/summernote-rails"
gem 'words_counted' # Year in Review
gem 'zip-zip'
gem "chartkick", "~> 5"
gem "loofah", ">= 2.5"

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
gem 'tilt', '~> 2.0', '>= 2.0.10'
gem 'haml'
gem 'rack-affiliates' # for tracking referrers
gem 'rinku' # linkify urls & emails in entries

# Assets
gem 'autoprefixer-rails'
# gem 'haml_assets'
gem 'i18n-js'
gem 'jquery-rails'
gem 'sass-rails'
gem 'twbs_sass_rails'
gem 'uglifier'

gem 'logtail-rails'
gem "sentry-ruby", "~> 5.9"
gem "sentry-rails", "~> 5.9"
gem "rack-attack" # Request blocking & throttling
gem "cloudflare-rails"
gem "stripe"
gem "stripe_event"
gem "reverse_markdown" # text export conversion html->txt
gem "redcarpet" # markdown rendering

group :development, :test do
  gem 'byebug'
  gem 'delorean'
  gem 'factory_bot_rails'
  gem 'faker'
  gem "rspec-rails"
  gem 'listen'
end

group :development do
  gem 'awesome_print', '~> 1.9', '>= 1.9.2'
  gem 'better_errors', '~> 2.9', '>= 2.9.1'
  gem 'binding_of_caller'
  gem 'bullet'
  gem 'meta_request'
  gem 'spring'
  gem 'spring-commands-rspec'

  # USE_SERVER=puma bundle exec derailed exec perf:mem
  # USE_SERVER=puma bundle exec derailed exec perf:mem_over_time
  gem 'derailed_benchmarks'
  gem 'stackprof'
end

group :test do
  gem 'capybara', '~> 3.35', '>= 3.35.3'
  gem 'database_cleaner'
  gem 'email_spec', require: false
  gem 'rspec', '~> 3.10'
  gem 'selenium-webdriver'
  gem 'simplecov', require: false
  gem 'webmock', require: false
end

gem 'rack-timeout'
