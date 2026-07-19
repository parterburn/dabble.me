require 'rails_helper'

RSpec.describe ImageUploader, '#relocate_between_dates!' do
  include_context 'has all objects'

  let(:from_date) { Date.new(2026, 7, 18) }
  let(:to_date) { Date.new(2026, 7, 17) }
  let(:filename) { 'journal-photo.jpg' }
  let(:entry) do
    paid_entry.tap do |e|
      e.update_columns(date: to_date, image: filename)
    end
  end
  let(:uploader) { entry.image }

  def fog_file_double(exists:)
    instance_double(CarrierWave::Storage::Fog::File, exists?: exists).tap do |file|
      allow(file).to receive(:copy_to)
      allow(file).to receive(:delete)
    end
  end

  it 'copies the original and version keys from the old date path to the new one' do
    storage = instance_double(CarrierWave::Storage::Fog)
    allow(CarrierWave::Storage::Fog).to receive(:new).and_return(storage)

    old_original = fog_file_double(exists: true)
    old_jpeg = fog_file_double(exists: true)
    missing = fog_file_double(exists: false)

    allow(CarrierWave::Storage::Fog::File).to receive(:new) do |_uploader, _storage, key|
      case key
      when %r{/2026-07-18/journal-photo\.jpg\z} then old_original
      when %r{/2026-07-18/jpeg_journal-photo\.jpg\z} then old_jpeg
      else missing
      end
    end

    uploader.relocate_between_dates!(from_date, to_date)

    expect(old_original).to have_received(:copy_to).with(%r{/2026-07-17/journal-photo\.jpg\z})
    expect(old_original).to have_received(:delete)
    expect(old_jpeg).to have_received(:copy_to).with(%r{/2026-07-17/jpeg_journal-photo\.jpg\z})
    expect(old_jpeg).to have_received(:delete)
  end

  it 'does nothing when the dates are the same' do
    expect(CarrierWave::Storage::Fog::File).not_to receive(:new)
    uploader.relocate_between_dates!(from_date, from_date)
  end
end
