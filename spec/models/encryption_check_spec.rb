require 'rails_helper'

RSpec.describe EncryptionCheck do
  it 'creates one encrypted row and passes on later runs' do
    expect(described_class.verify!).to be(true)
    expect(described_class.verify!).to be(true)
    expect(described_class.count).to eq(1)
    expect(ciphertext?(stored_value(described_class.first, 'value'))).to be(true)
    expect(ciphertext?(stored_value(described_class.first, 'lookup'))).to be(true)
  end

  it 'encrypts its row even before ciphertext writes are turned on' do
    with_env('ACTIVE_RECORD_ENCRYPTION_WRITE' => 'false') { described_class.verify! }
    expect(ciphertext?(stored_value(described_class.first, 'value'))).to be(true)
  end

  it 'fails when the stored row was written with other keys' do
    described_class.verify!
    other_keys = '{"p":"AAAA","h":{"iv":"AAAAAAAAAAAAAAAA","at":"AAAAAAAAAAAAAAAAAAAAAA=="}}'
    store_plaintext(described_class.first, 'value', other_keys)

    expect { described_class.verify! }.to raise_error(described_class::Failed, /does not decrypt/)
  end

  it 'fails when the deterministic key differs' do
    described_class.verify!
    store_plaintext(described_class.first, 'lookup', described_class.first.then { |row| stored_value(row, 'lookup').sub(/"p":"./, '"p":"_') })

    expect { described_class.verify! }.to raise_error(described_class::Failed, /does not decrypt/)
  end

  it 'fails when a key is not set' do
    config = ActiveRecord::Encryption.config
    original = config.primary_key
    config.primary_key = nil

    expect { described_class.verify! }.to raise_error(described_class::Failed, /ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY/)
  ensure
    config.primary_key = original
  end

  it 'cannot hold a second row' do
    described_class.verify!
    expect { described_class.create!(value: 'another', lookup: 'another') }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
