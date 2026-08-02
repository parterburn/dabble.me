# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportDayOneJob, type: :job do
  include_context "has all objects"
  include ActiveJob::TestHelper

  after { FileUtils.rm_rf(ImportUploadStore::BASE_DIR) }

  it "imports entries, emails the user, and cleans up the upload" do
    dir = ImportUploadStore::BASE_DIR.join("day_one", paid_user.user_key, SecureRandom.uuid)
    FileUtils.mkdir_p(dir)
    zip_path = dir.join("upload.zip")

    require "zip"
    Zip::File.open(zip_path, create: true) do |zip|
      zip.get_output_stream("Journal.json") do |f|
        f.write({
          "entries" => [
            {
              "creationDate" => "2018-05-05T10:00:00Z",
              "timeZone" => "UTC",
              "text" => "Job import works"
            }
          ]
        }.to_json)
      end
    end

    expect {
      described_class.perform_now(paid_user.id, zip_path.to_s)
    }.to have_enqueued_job(ActionMailer::MailDeliveryJob)

    entry = paid_user.existing_entry("2018-05-05")
    expect(entry.body).to include("Job import works")
    expect(entry.inspiration.category).to eq("Day One")
    expect(File.exist?(dir)).to eq(false)
  end
end
