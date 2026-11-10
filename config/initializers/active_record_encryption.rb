# frozen_string_literal: true

# Every `encrypts` attribute goes through the staged encryptor, which reads
# ciphertext always and writes it once ACTIVE_RECORD_ENCRYPTION_WRITE=true.
# Keys and the plaintext allowance are set in config/application.rb.
Rails.application.config.to_prepare do
  ActiveRecord::Encryption.default_context.encryptor = Encryption::StagedEncryptor.new

  # Derive the key once at boot rather than on a request. Without keys there
  # is nothing to derive; EncryptionCheck reports that when a server starts.
  begin
    ActiveRecord::Encryption.default_context.key_provider
  rescue ActiveRecord::Encryption::Errors::Configuration
    nil
  end
end
