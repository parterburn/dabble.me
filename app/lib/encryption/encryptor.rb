# frozen_string_literal: true

module Encryption
  # The app's encryptor (set in config/initializers/active_record_encryption.rb).
  # Every save writes ciphertext. `forcing(:plaintext)` writes the clear value
  # instead, which is how `encryption:decrypt` returns a row to plaintext.
  class Encryptor < ActiveRecord::Encryption::Encryptor
    def self.forcing(mode)
      previous = Thread.current[:encryption_write_mode]
      Thread.current[:encryption_write_mode] = mode
      yield
    ensure
      Thread.current[:encryption_write_mode] = previous
    end

    def encrypt(clear_text, **options)
      return clear_text if Thread.current[:encryption_write_mode] == :plaintext

      super
    end
  end
end
