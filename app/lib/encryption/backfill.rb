# frozen_string_literal: true

module Encryption
  # Encrypts (or decrypts) rows written before encryption was turned on, and
  # reports how many are left. Run through the `encryption:*` rake tasks.
  #
  # Every row is changed under a row lock and inside its own transaction, then
  # read back and compared with what it held before. A row that does not read
  # back identical is rolled back and the run stops.
  class Backfill
    class VerificationFailed < StandardError; end

    MODELS = [Entry, User, Hashtag].freeze
    BATCH_SIZE = 500

    Result = Struct.new(:checked, :changed, :remaining, keyword_init: true)

    # user_id limits the run to one account: its entries, its hashtags and its
    # own row.
    def initialize(user_id: nil, pause: 0, out: $stdout)
      @user_id = user_id
      @pause = pause
      @out = out
    end

    # Rows that still hold plaintext in at least one encrypted column, per model.
    def status
      each_model.to_h do |model, scope|
        remaining = 0
        each_record(scope) { |record| remaining += 1 if plaintext_attributes(record).any? }
        [model.name, Result.new(checked: scope.count, changed: 0, remaining: remaining)]
      end
    end

    # Encrypts and decrypts every value in memory and compares the result.
    # Writes nothing, so it is safe to run against production at any time.
    def rehearse
      each_model.to_h do |model, scope|
        checked = 0
        each_record(scope) do |record|
          model.encrypted_attributes.each { |attribute| rehearse_attribute!(record, attribute) }
          checked += 1
        end
        report "#{model.name}: #{checked} rows round-trip"
        [model.name, Result.new(checked: checked, changed: 0, remaining: 0)]
      end
    end

    def encrypt
      unless StagedEncryptor.write_ciphertext?
        raise VerificationFailed, "Set ACTIVE_RECORD_ENCRYPTION_WRITE=true on every process before encrypting existing rows."
      end

      EncryptionCheck.verify!
      convert { |record| plaintext_attributes(record).any? && rewrite(record, :ciphertext) }
    end

    # The way back: returns every row to plaintext.
    def decrypt
      unless ActiveRecord::Encryption.config.support_unencrypted_data
        raise VerificationFailed, "Plaintext rows are not allowed (ACTIVE_RECORD_ENCRYPTION_ALLOW_PLAINTEXT=false)."
      end

      convert(expect_encrypted: false) { |record| encrypted_attributes(record).any? && rewrite(record, :plaintext) }
    end

    private

    def each_model
      MODELS.map { |model| [model, scope_for(model)] }
    end

    def scope_for(model)
      scope = model.unscoped
      return scope if @user_id.nil?

      model == User ? scope.where(id: @user_id) : scope.where(user_id: @user_id)
    end

    def each_record(scope, &block)
      scope.in_batches(of: BATCH_SIZE) do |batch|
        batch.each(&block)
        sleep(@pause) if @pause.positive?
      end
    end

    def convert(expect_encrypted: true)
      each_model.to_h do |model, scope|
        checked = changed = 0
        scope.in_batches(of: BATCH_SIZE) do |batch|
          batch.pluck(:id).each do |id|
            checked += 1
            changed += 1 if convert_row(model, id, expect_encrypted) { |record| yield record }
          end
          report "#{model.name}: #{checked} checked, #{changed} changed"
          sleep(@pause) if @pause.positive?
        end
        [model.name, Result.new(checked: checked, changed: changed, remaining: 0)]
      end
    end

    # Locks the row so nothing else can write it between reading its values
    # and replacing them, and rolls back unless it reads back unchanged.
    def convert_row(model, id, expect_encrypted)
      model.transaction do
        record = model.unscoped.lock.find_by(id: id)
        next false if record.nil?

        before = values_of(record)
        next false unless yield(record)

        verify_row!(model, id, before, expect_encrypted)
        true
      end
    end

    # Writes every encrypted column again in the given form. update_columns
    # skips callbacks, validations and updated_at.
    def rewrite(record, mode)
      StagedEncryptor.forcing(mode) { record.update_columns(values_of(record)) }
      true
    end

    def verify_row!(model, id, before, expect_encrypted)
      fresh = model.unscoped.find(id)
      model.encrypted_attributes.each do |attribute|
        unless fresh.read_attribute(attribute) == before[attribute]
          raise VerificationFailed, "#{model.name} #{id} #{attribute} did not read back identical; the row was rolled back."
        end
        next if raw_value(fresh, attribute).nil?
        next if fresh.encrypted_attribute?(attribute) == expect_encrypted

        raise VerificationFailed, "#{model.name} #{id} #{attribute} is #{expect_encrypted ? 'still plaintext' : 'still encrypted'}; the row was rolled back."
      end
    end

    def rehearse_attribute!(record, attribute)
      value = record.read_attribute(attribute)
      return if value.nil?

      type = record.class.type_for_attribute(attribute)
      cipher = StagedEncryptor.forcing(:ciphertext) { type.serialize(value) }
      survived = ActiveRecord::Encryption.encryptor.encrypted?(cipher) && type.deserialize(cipher) == value
      return if survived

      raise VerificationFailed, "#{record.class.name} #{record.id} #{attribute} does not survive encryption."
    end

    def values_of(record)
      record.class.encrypted_attributes.index_with { |attribute| record.read_attribute(attribute) }
    end

    def plaintext_attributes(record)
      record.class.encrypted_attributes.select do |attribute|
        !raw_value(record, attribute).nil? && !record.encrypted_attribute?(attribute)
      end
    end

    def encrypted_attributes(record)
      record.class.encrypted_attributes.select { |attribute| record.encrypted_attribute?(attribute) }
    end

    def raw_value(record, attribute)
      record.read_attribute_before_type_cast(attribute)
    end

    def report(message)
      @out&.puts(message)
    end
  end
end
