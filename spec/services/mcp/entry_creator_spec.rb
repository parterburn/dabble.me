# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::EntryCreator do
  include_context "has all objects"

  before do
    # CI sets AWS_BUCKET=test (see .github/workflows/test.yml); dev machines may use dabble-me from local_env.yml.
    # Stub whatever host/path Fog uses for this app's configured bucket (virtual-hosted and path-style S3 URLs).
    bucket = CarrierWave::Uploader::Base.fog_directory
    s3_patterns = [
      %r{\Ahttps://#{Regexp.escape(bucket)}\.s3(?:\.[a-z0-9-]+)*\.amazonaws\.com/}i,
      %r{\Ahttps://s3(?:\.[a-z0-9-]+)*\.amazonaws\.com/#{Regexp.escape(bucket)}/}i
    ]
    s3_patterns.each do |s3|
      stub_request(:put, s3).to_return(
        status: 200,
        body: %(<?xml version="1.0" encoding="UTF-8"?>\n<PutObjectResult><ETag>"stub"</ETag></PutObjectResult>\n),
        headers: { "Content-Type" => "application/xml", "ETag" => '"stub"' }
      )
      stub_request(:head, s3).to_return(
        status: 200,
        body: "",
        headers: {
          "Content-Type" => "image/png",
          "Content-Length" => "70",
          "Last-Modified" => "Wed, 01 Jan 2020 00:00:00 GMT",
          "ETag" => '"stub"'
        }
      )
      stub_request(:delete, s3).to_return(status: 204, body: "", headers: {})
    end
  end

  def clear_calendar_day!(user, date)
    tz = ActiveSupport::TimeZone[user.send_timezone] || Time.zone
    day_start = tz.local(date.year, date.month, date.day).beginning_of_day
    user.entries.where(date: day_start..day_start.end_of_day).delete_all
  end

  # 1x1 transparent PNG
  let(:png_bytes) do
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  end

  describe "#create" do
    it "rejects both image_url and image_base64" do
      result = Mcp::EntryCreator.new(user: paid_user).create(
        date_string: "2099-01-02",
        body_text: "hello",
        image_url: "https://example.com/a.png",
        image_base64: Base64.strict_encode64(png_bytes)
      )
      expect(result[:success]).to eq(false)
      expect(result[:errors].first).to include("only one of image_url")
    end

    it "rejects private-host image URLs before fetching" do
      result = Mcp::EntryCreator.new(user: paid_user).create(
        date_string: "2099-01-03",
        body_text: "hello",
        image_url: "http://127.0.0.1/secret.png"
      )
      expect(result[:success]).to eq(false)
      expect(result[:errors].first).to include("not allowed")
    end

    it "downloads image_url and saves an entry with an image", :aggregate_failures do
      stub_request(:get, "https://example.com/mcp-face.png")
        .to_return(status: 200, body: png_bytes, headers: { "Content-Type" => "image/png" })

      clear_calendar_day!(paid_user, Date.new(2099, 1, 10))

      result = Mcp::EntryCreator.new(user: paid_user).create(
        date_string: "2099-01-10",
        body_text: "with photo",
        image_url: "https://example.com/mcp-face.png"
      )

      expect(result[:success]).to eq(true)
      expect(result[:entry][:has_image]).to eq(true)
      entry = paid_user.entries.find(result[:entry][:id])
      expect(entry.image).to be_present
      expect(entry.body).to include("with photo")
      expect(result[:entry][:url]).to eq("http://[REDACTED]/entries/2099/1/10")
    end

    it "accepts a data-URL image_base64 without body text" do
      clear_calendar_day!(paid_user, Date.new(2099, 1, 11))

      data_url = "data:image/png;base64,#{Base64.strict_encode64(png_bytes)}"
      result = Mcp::EntryCreator.new(user: paid_user).create(
        date_string: "2099-01-11",
        body_text: "",
        image_base64: data_url
      )

      expect(result[:success]).to eq(true)
      expect(result[:entry][:has_image]).to eq(true)
      expect(result[:entry][:url]).to eq("http://[REDACTED]/entries/2099/1/11")
    end
  end
end
