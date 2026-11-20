# frozen_string_literal: true

# Keys are set in config/application.rb. Derive the key once at boot rather
# than on a request. Without keys there is nothing to derive; EncryptionCheck
# reports that when a server starts.
Rails.application.config.to_prepare do
  begin
    ActiveRecord::Encryption.default_context.key_provider
  rescue ActiveRecord::Encryption::Errors::Configuration
    nil
  end
end
