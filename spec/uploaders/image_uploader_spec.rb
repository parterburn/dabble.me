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

RSpec.describe ImageUploader, '#store_dir' do
  include_context 'has all objects'

  let(:date) { Date.new(2026, 7, 17) }

  before { paid_entry.update_columns(date: date, image: 'journal-photo.jpg') }

  it "keeps an existing user's folder, where image_key was copied from user_key" do
    paid_user.update_column(:image_key, paid_user.user_key)

    expect(paid_entry.reload.image.store_dir).to eq("uploads/development/#{paid_user.user_key}/2026-07-17")
  end

  it 'uses image_key, not the posting key' do
    paid_user.update_column(:image_key, 'uphotofolder123456789')

    expect(paid_entry.reload.image.store_dir).to eq('uploads/development/uphotofolder123456789/2026-07-17')
  end

  it 'does not move when the posting key changes' do
    store_dir = paid_entry.image.store_dir
    paid_user.update_column(:user_key, User.generate_unique_key)

    expect(paid_entry.reload.image.store_dir).to eq(store_dir)
  end

  it 'falls back to user_key for an account created before image_key existed' do
    paid_user.update_column(:image_key, nil)

    expect(paid_entry.reload.image.store_dir).to eq("uploads/development/#{paid_user.user_key}/2026-07-17")
  end
end

RSpec.describe ImageUploader, '#filename' do
  include_context 'has all objects'

  # 1x1 transparent PNG
  let(:png_bytes) { Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==') }
  let(:dir) { Dir.mktmpdir }
  let(:upload) do
    path = File.join(dir, 'upload.png')
    File.binwrite(path, png_bytes)
    Rack::Test::UploadedFile.new(path, 'image/png', original_filename: 'IMG_8880.png')
  end

  # CarrierWave caches through fog too, so cache! PUTs the upload to
  # uploads/tmp/ on S3. Same stubbing as spec/services/mcp/entry_creator_spec.rb.
  before do
    bucket = Regexp.escape(CarrierWave::Uploader::Base.fog_directory)
    [
      %r{\Ahttps://#{bucket}\.s3(?:\.[a-z0-9-]+)*\.amazonaws\.com/}i,
      %r{\Ahttps://s3(?:\.[a-z0-9-]+)*\.amazonaws\.com/#{bucket}/}i
    ].each do |s3|
      stub_request(:put, s3).to_return(status: 200, body: '', headers: { 'ETag' => '"stub"' })
    end
  end

  after { FileUtils.rm_rf(dir) }

  it 'puts 8 random characters in front of the original name of a new upload' do
    uploader = paid_entry.image
    uploader.cache!(upload)

    expect(uploader.filename).to match(/\A[0-9a-z]{8}-IMG_8880\.png\z/)
    expect(uploader.filename).to eq(uploader.filename)
  end

  it 'uses a different prefix for a different upload' do
    first = paid_entry.image.tap { |u| u.cache!(upload) }.filename
    second = Entry.find(paid_entry.id).image.tap { |u| u.cache!(upload) }.filename

    expect(first).not_to eq(second)
  end

  it 'keeps the name of a photo that is already stored' do
    paid_entry.update_columns(date: Date.new(2026, 7, 17), image: 'IMG_0001.jpeg')
    uploader = paid_entry.reload.image

    expect(uploader.filename).to be_nil
    expect(uploader.identifier).to eq('IMG_0001.jpeg')
    expect(uploader.store_path).to end_with('/2026-07-17/IMG_0001.jpeg')
  end
end
