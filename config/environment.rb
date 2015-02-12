# Load the Rails application.
require File.expand_path('../application', __FILE__)

# Initialize the Rails application.
Rails.application.initialize!

Mime::Type.register "text/txt", :txt

if Rails.env.development?
  Rails.logger = Le.new("#{ENV['LOGENTRIES_KEY']}", true)
else
  Rails.logger = Le.new("#{ENV['LOGENTRIES_KEY']}", local: true)
end