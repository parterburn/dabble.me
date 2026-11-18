# frozen_string_literal: true

require "rails_helper"

RSpec.describe "stored image policy" do
  it "turns CarrierWave download checks back on and refuses octet-stream" do
    expect(CarrierWave::Uploader::Base.validate_download).to eq(true)
    expect(Entry::ALLOWED_IMAGE_TYPES).not_to include("application/octet-stream")
    expect(ImageUploader.new.content_type_allowlist.any? { |pattern| pattern.match?("application/octet-stream") }).to eq(false)
  end

  it "only treats this app's bucket and CDN as downloadable image URLs" do
    bucket = CarrierWave::Uploader::Base.fog_directory
    expect(ImageUploader.application_upload_url?("https://#{bucket}.s3.amazonaws.com/uploads/a.jpg")).to eq(true)
    expect(ImageUploader.application_upload_url?("https://d10r8m94hrfowu.cloudfront.net/uploads/a.jpg")).to eq(true)
    expect(ImageUploader.application_upload_url?("http://169.254.169.254/latest/meta-data")).to eq(false)
    expect(ImageUploader.application_upload_url?("https://evil.example/a.jpg")).to eq(false)
  end
end
