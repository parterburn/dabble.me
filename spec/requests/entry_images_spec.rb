# frozen_string_literal: true

require "rails_helper"

# Pages that show photos must build image URLs from the stored filename.
# Asking CarrierWave whether the S3 file exists sends a HEAD request per photo,
# which made a page of entries take ~6 seconds in production. WebMock blocks
# outside HTTP in specs, so any such request fails these examples.
RSpec.describe "Entry images", type: :request do
  include_context "has all objects"

  let(:s3) { /amazonaws\.com/ }
  let!(:photo_entry) do
    create(:entry, user: paid_user, body: "<p>With a photo</p>", date: 2.days.ago).tap do |e|
      e.update_columns(image: "lake.jpg")
    end
  end

  before { sign_in paid_user }

  it "lists photo entries without asking S3 whether each file exists" do
    get entries_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("/lake.jpg")
    expect(WebMock).not_to have_requested(:any, s3)
  end

  it "marks photo entries in the calendar feed without asking S3" do
    get entries_path(format: :json, start: 1.week.ago.to_date.iso8601, end: Date.tomorrow.iso8601)

    titles = JSON.parse(response.body).map { |event| event["title"] }
    expect(titles).to include(a_string_starting_with("📸"))
    expect(WebMock).not_to have_requested(:any, s3)
  end

  it "shows the remove-photo option on the edit page without asking S3" do
    get edit_entry_path(photo_entry)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("remove_image")
    expect(WebMock).not_to have_requested(:any, s3)
  end

  describe "stored image checks" do
    it "reads the image column" do
      expect(photo_entry.reload.image_stored?).to be(true)
      expect(create(:entry, user: paid_user).image_stored?).to be(false)
    end

    it "spots stored HEIC originals by name, so their JPEG version is still served" do
      heic_entry = create(:entry, user: paid_user).tap { |e| e.update_columns(image: "IMG_1.HEIC") }
      uploader = heic_entry.reload.image

      expect(uploader.version_active?(:jpeg)).to be(true)
      expect(photo_entry.reload.image.version_active?(:jpeg)).to be(false)
      expect(WebMock).not_to have_requested(:any, s3)
    end
  end
end
