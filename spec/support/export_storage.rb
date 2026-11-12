# Runs a spec against Fog's in-memory S3, for anything that stores exports.
RSpec.shared_context 'with export storage' do
  around do |example|
    Fog.mock!
    Fog::Mock.reset
    Fog::Storage.new(CarrierWave::Uploader::Base.fog_credentials).directories.create(key: ENV.fetch('AWS_BUCKET'))
    example.run
  ensure
    Fog::Mock.reset
    Fog.unmock!
  end
end
