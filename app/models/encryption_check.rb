# One encrypted row that proves a process holds the right encryption keys.
#
# With unencrypted data still allowed, a row that fails to decrypt reads back
# as its raw ciphertext instead of raising. A process started with missing or
# different keys would show that to users, or save it back as if it were the
# entry. verify! runs when a web or worker process starts and stops it first.
class EncryptionCheck < ActiveRecord::Base
  class Failed < StandardError; end

  EXPECTED = "dabble-me-encryption-check".freeze
  KEY_SETTINGS = %i[primary_key deterministic_key key_derivation_salt].freeze

  # Always encrypted, whatever stage the rollout is at. `value` proves the
  # primary key and salt; `lookup` is deterministic, so it proves the
  # deterministic key that posting and photo key lookups depend on.
  encrypts :value, encryptor: ActiveRecord::Encryption::Encryptor.new
  encrypts :lookup, deterministic: true, encryptor: ActiveRecord::Encryption::Encryptor.new

  CHECKED = %i[value lookup].freeze

  def self.verify!
    missing = KEY_SETTINGS.reject { |setting| key_set?(setting) }
    if missing.any?
      names = missing.map { |setting| "ACTIVE_RECORD_ENCRYPTION_#{setting.to_s.upcase}" }
      raise Failed, "Encryption keys are not set: #{names.join(', ')}"
    end

    check = first || create_check
    unless CHECKED.all? { |column| check.encrypted_attribute?(column) && check.public_send(column) == EXPECTED }
      raise Failed, "The stored encryption check does not decrypt with this process's keys. " \
                    "Another process wrote it with different keys; do not start until they match."
    end
    true
  end

  def self.key_set?(setting)
    ActiveRecord::Encryption.config.public_send(setting).present?
  rescue ActiveRecord::Encryption::Errors::Configuration
    false
  end
  private_class_method :key_set?

  def self.create_check
    create!(value: EXPECTED, lookup: EXPECTED)
  rescue ActiveRecord::RecordNotUnique
    first
  end
  private_class_method :create_check
end
