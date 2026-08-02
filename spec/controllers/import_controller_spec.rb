# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportController, type: :controller do
  include_context "has all objects"
  # ActiveJob::TestHelper enables/disables a per-example test adapter via
  # before_setup/after_teardown. Do not also assign ActiveJob::Base.queue_adapter
  # around examples — capturing queue_adapter while the test adapter is active
  # and writing it back leaks TestAdapter into later examples, so deliver_later
  # stops delivering into ActionMailer::Base.deliveries.
  include ActiveJob::TestHelper

  after { FileUtils.rm_rf(ImportUploadStore::BASE_DIR) }

  describe "PUT #update trailmix" do
    it "rejects non-json uploads for trailmix" do
      sign_in paid_user
      file = Tempfile.new(["xss", ".html"])
      file.write("<script>alert(1)</script>")
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "text/html", original_filename: "xss.html")

      put :update, params: { type: "trailmix", json_file: upload }

      expect(response).to redirect_to(import_path(type: "trailmix"))
      expect(flash[:alert]).to match(/Only \.json/)
      expect(ImportTrailmixJob).not_to have_been_enqueued
    ensure
      file.close!
    end

    it "enqueues a job with a path under tmp/imports" do
      sign_in paid_user
      file = Tempfile.new(["entries", ".json"])
      file.write('[{"body":"hello","date":"2020-01-01"}]')
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: "entries.json")

      expect {
        put :update, params: { type: "trailmix", json_file: upload }
      }.to have_enqueued_job(ImportTrailmixJob).with { |_user_id, path|
        expect(path).to start_with(ImportUploadStore::BASE_DIR.to_s)
        expect(path).not_to include("public/")
        expect(File.basename(path)).to eq("upload.json")
      }

      expect(response).to redirect_to(entries_path)
    ensure
      file.close!
    end
  end

  describe "PUT #update day_one" do
    it "rejects non-zip uploads for day_one" do
      sign_in paid_user
      file = Tempfile.new(["not", ".json"])
      file.write("{}")
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: "Journal.json")

      put :update, params: { type: "day_one", zip_file: upload }

      expect(response).to redirect_to(import_path(type: "day_one"))
      expect(flash[:alert]).to match(/Only \.zip/)
      expect(ImportDayOneJob).not_to have_been_enqueued
    ensure
      file.close!
    end

    it "enqueues ImportDayOneJob with a path under tmp/imports" do
      sign_in paid_user
      file = Tempfile.new(["journal", ".zip"])
      file.write("PK\x03\x04fake")
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "application/zip", original_filename: "Journal.zip")

      expect {
        put :update, params: { type: "day_one", zip_file: upload }
      }.to have_enqueued_job(ImportDayOneJob).with { |_user_id, path|
        expect(path).to start_with(ImportUploadStore::BASE_DIR.to_s)
        expect(path).to include("/day_one/")
        expect(File.basename(path)).to eq("upload.zip")
      }

      expect(response).to redirect_to(entries_path)
      expect(flash[:notice]).to match(/Day One import has started/)
    ensure
      file.close!
    end
  end

  describe "POST #process_ohlife_images" do
    it "rejects non-zip uploads" do
      sign_in paid_user
      file = Tempfile.new(["photos", ".txt"])
      file.write("not a zip")
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "text/plain", original_filename: "photos.txt")

      post :process_ohlife_images, params: { zip_file: upload }

      expect(response).to redirect_to(import_path(type: "photos"))
      expect(flash[:alert]).to match(/Only \.zip/)
      expect(ImportJob).not_to have_been_enqueued
    ensure
      file.close!
    end
  end
end
