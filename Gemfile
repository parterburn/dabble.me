source 'https://rubygems.org'

ruby '2.2.3'
gem 'rails', '4.2.4'

# Servers
gem 'puma'

# ORM
gem 'pg'

# users
gem 'devise', '~> 3.4.0'
gem 'gibbon' # mailchimp connector

gem 'addressable' # better URI checking
gem 'sinatra', '>= 1.3.0', require: nil
gem 'combined_time_select', '~> 1.0.1'

# email parsing
gem 'sendgrid', '~> 1.2.0' # Emails
gem 'griddler', '~> 1.1.0'
gem 'griddler-sendgrid'
gem 'email_reply_parser'

gem 'randomized_field', '~> 0.1.0' # builds user_keys
gem 'filepicker-rails', '~> 2.1.0' # image uploads
gem 'summernote-rails' # wysiwyg
gem 'rest-client' # RESTClient
gem 'rubyzip', '~> 1.1.6'
gem 'zip-zip'
gem 'rack-utf8_sanitizer'

gem 'kaminari' # Pagination

# Miscellanea
gem 'google-analytics-rails'
gem 'haml'

# Assets
gem 'autoprefixer-rails'
gem 'coffee-rails', '~> 4.0.0'
gem 'haml_assets'
gem 'i18n-js'
gem 'jquery-rails'
gem 'sass-rails', '~> 4.0.3'
gem 'twbs_sass_rails'
gem 'uglifier', '>= 1.3.0'

gem 'le' # logentries
gem 'newrelic_rpm'

group :development, :test do
  gem 'byebug'
  gem 'delorean'
  gem 'factory_girl_rails'
  gem 'faker'
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
  gem 'pry'
  gem 'pry-remote'
  gem 'pry-stack_explorer'
end

group :test do
  gem 'capybara'
  gem 'coveralls', require: false
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
