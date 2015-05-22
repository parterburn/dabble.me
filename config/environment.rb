# Load the Rails application.
require File.expand_path('../application', __FILE__)

# Initialize the Rails application.
Rails.application.initialize!

Mime::Type.register "text/txt", :txt

Rails.logger = Le.new(ENV['LOGENTRIES_KEY'], :debug => true, :local => true)