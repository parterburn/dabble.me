# frozen_string_literal: true

require "rails_helper"
require "zip"

RSpec.describe DayOneImporter do
  include_context "has all objects"

  def build_zip(entries:, photos: {})
    path = Rails.root.join("tmp", "day_one_spec_#{SecureRandom.hex}.zip")
    FileUtils.mkdir_p(File.dirname(path))
    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream("Journal.json") do |f|
        f.write(JSON.pretty_generate("entries" => entries))
      end
      photos.each do |filename, bytes|
        zip.get_output_stream("photos/#{filename}") { |f| f.write(bytes) }
      end
    end
    path.to_s
  end

  # 1x1 JPEG
  let(:tiny_jpeg) do
    Base64.decode64("/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGfAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAQUCf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQMBAT8Bf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8Bf//Z")
  end

  after do
    Dir.glob(Rails.root.join("tmp", "day_one_spec_*.zip")).each { |f| FileUtils.rm_f(f) }
  end

  describe "#import!" do
    it "imports markdown entries with the Day One inspiration tag" do
      zip = build_zip(entries: [
        {
          "creationDate" => "2020-06-15T18:30:00Z",
          "timeZone" => "America/Los_Angeles",
          "text" => "# Hello\n\nThis is **bold** and a photo ![](dayone-moment://ABC123)."
        }
      ])

      result = described_class.new(user: paid_user, zip_path: zip).import!

      expect(result.imported).to eq(1)
      expect(result.errors).to be_empty
      entry = paid_user.entries.find_by("date >= ? AND date < ?", Date.new(2020, 6, 15), Date.new(2020, 6, 16))
      expect(entry).to be_present
      # 18:30 UTC on 2020-06-15 is 11:30 PDT → still June 15
      expect(entry.date.to_date).to eq(Date.new(2020, 6, 15))
      expect(entry.body).to include("<strong>bold</strong>")
      expect(entry.body).to include("Hello")
      expect(entry.body).not_to include("dayone-moment")
      expect(entry.inspiration.category).to eq("Day One")
    end

    it "merges multiple Day One entries on the same local calendar day" do
      zip = build_zip(entries: [
        {
          "creationDate" => "2021-01-02T08:00:00Z",
          "timeZone" => "UTC",
          "text" => "Morning thoughts"
        },
        {
          "creationDate" => "2021-01-02T20:00:00Z",
          "timeZone" => "UTC",
          "text" => "Evening thoughts"
        }
      ])

      result = described_class.new(user: paid_user, zip_path: zip).import!

      expect(result.imported).to eq(1)
      entry = paid_user.existing_entry("2021-01-02")
      expect(entry.body).to include("Morning thoughts")
      expect(entry.body).to include("Evening thoughts")
      expect(entry.body).to include("<hr>")
    end

    it "skips dates that already have a Dabble Me entry" do
      paid_user.entries.create!(date: Date.new(2019, 3, 1), body: "<p>Existing</p>")
      zip = build_zip(entries: [
        {
          "creationDate" => "2019-03-01T12:00:00Z",
          "timeZone" => "UTC",
          "text" => "Should not import"
        }
      ])

      result = described_class.new(user: paid_user, zip_path: zip).import!

      expect(result.imported).to eq(0)
      expect(result.skipped.join).to match(/already exists/)
      expect(paid_user.existing_entry("2019-03-01").body).to include("Existing")
    end

    it "attaches a single photo when present" do
      md5 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      zip = build_zip(
        entries: [
          {
            "creationDate" => "2022-04-01T12:00:00Z",
            "timeZone" => "UTC",
            "text" => "With photo",
            "photos" => [
              { "identifier" => "ID1", "md5" => md5, "type" => "jpeg", "orderInEntry" => 0 }
            ]
          }
        ],
        photos: { "#{md5}.jpeg" => tiny_jpeg }
      )

      allow_any_instance_of(ImageUploader).to receive(:cache!)
      allow_any_instance_of(ImageUploader).to receive(:store!)

      result = described_class.new(user: paid_user, zip_path: zip).import!

      expect(result.imported).to eq(1)
      expect(result.errors).to be_empty
      entry = paid_user.existing_entry("2022-04-01")
      expect(entry.body).to include("With photo")
      expect(entry.image_error).to be_blank
    end

    it "rejects ZIPs without a journal JSON file" do
      path = Rails.root.join("tmp", "day_one_spec_empty_#{SecureRandom.hex}.zip")
      Zip::File.open(path, create: true) do |zip|
        zip.get_output_stream("readme.txt") { |f| f.write("no json here") }
      end

      expect {
        described_class.new(user: paid_user, zip_path: path.to_s).import!
      }.to raise_error(ArgumentError, /No JSON/)
    end
  end
end
