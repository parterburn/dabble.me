# frozen_string_literal: true

# Every `encrypts` attribute uses Encryption::Encryptor, which writes
# ciphertext. `forcing(:plaintext)` is how `encryption:decrypt` writes a row
# back as plaintext. Keys and the plaintext allowance are set in
# config/application.rb.
Rails.application.config.to_prepare do
  ActiveRecord::Encryption.default_context.encryptor = Encryption::Encryptor.new

  # Derive the key once at boot rather than on a request. Without keys there
  # is nothing to derive; EncryptionCheck reports that when a server starts.
  begin
    ActiveRecord::Encryption.default_context.key_provider
  rescue ActiveRecord::Encryption::Errors::Configuration
    nil
  end
end
