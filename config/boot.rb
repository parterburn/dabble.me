ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.

# ActiveSupport 6.1 references Logger::Severity without requiring 'logger'. It only
# loaded by accident via concurrent-ruby, which stopped requiring it eagerly in 1.3.5.
# Rails 7.1 requires it itself (rails/rails#54264), so this can go away on upgrade.
require 'logger'
