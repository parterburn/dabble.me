# frozen_string_literal: true

module Encryption
  # The app's encryptor (set in config/initializers/active_record_encryption.rb).
  # It always knows how to decrypt, but only writes ciphertext once
  # ACTIVE_RECORD_ENCRYPTION_WRITE=true. That makes turning encryption on a
  # two-step change: first every process learns to read ciphertext, then they
  # start writing it. A web and a worker process that restart minutes apart
  # can then never hand each other a row one of them cannot read.
  class StagedEncryptor < ActiveRecord::Encryption::Encryptor
    # Writes ciphertext (or plaintext) inside the block whatever the setting,
    # on this thread only. For rehearsing encryption before it is on, and for
    # returning rows to plaintext.
    def self.forcing(mode)
      previous = Thread.current[:encryption_staged_mode]
      Thread.current[:encryption_staged_mode] = mode
      yield
    ensure
      Thread.current[:encryption_staged_mode] = previous
    end

    def self.write_ciphertext?
      forced = Thread.current[:encryption_staged_mode]
      return forced == :ciphertext if forced

      ENV.fetch("ACTIVE_RECORD_ENCRYPTION_WRITE") { Rails.env.production? ? "false" : "true" } == "true"
    end

    def encrypt(clear_text, **options)
      return clear_text unless self.class.write_ciphertext?

      super
    end
  end
end
