# This file is used by Rack-based servers to start the application.

require ::File.expand_path('../config/environment',  __FILE__)
# Refuse to serve with missing or mismatched encryption keys.
EncryptionCheck.verify!

run Rails.application
