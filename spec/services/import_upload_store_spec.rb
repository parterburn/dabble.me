# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportUploadStore do
  let(:user_key) { "abc123userkey" }
  let(:tmpdir) { Dir.mktmpdir }
  let(:tempfile) do
    file = Tempfile.new(["upload", ".json"], tmpdir)
    file.write('[{"body":"hi","date":"2020-01-01"}]')
    file.rewind
    file
  end

  def uploaded_file(filename:, content_type:, tempfile:)
    ActionDispatch::Http::UploadedFile.new(
      filename: filename,
      type: content_type,
      tempfile: tempfile
    )
  end

  after do
    FileUtils.rm_rf(tmpdir)
    FileUtils.rm_rf(ImportUploadStore::BASE_DIR)
  end

  describe ".store!" do
    it "stores trailmix JSON outside public/ with a random filename" do
      upload = uploaded_file(filename: "evil.html.json", content_type: "application/json", tempfile: tempfile)

      path = described_class.store!(uploaded_file: upload, user_key: user_key, kind: "trailmix")

      expect(path).to start_with(ImportUploadStore::BASE_DIR.to_s)
      expect(path).not_to include("public/")
      expect(File.basename(path)).to eq("upload.json")
      expect(File.exist?(path)).to eq(true)
      expect(File.stat(path).mode & 0o777).to eq(0o600)
    end

    it "rejects non-json trailmix uploads" do
      html = Tempfile.new(["xss", ".html"], tmpdir)
      html.write("<script>alert(1)</script>")
      html.rewind
      upload = uploaded_file(filename: "xss.html", content_type: "text/html", tempfile: html)

      expect {
        described_class.store!(uploaded_file: upload, user_key: user_key, kind: "trailmix")
      }.to raise_error(ImportUploadStore::Error, /Only \.json/)
    end

    it "rejects zip uploads that are not .zip" do
      bad = Tempfile.new(["not", ".exe"], tmpdir)
      bad.write("MZ")
      bad.rewind
      upload = uploaded_file(filename: "photos.exe", content_type: "application/octet-stream", tempfile: bad)

      expect {
        described_class.store!(uploaded_file: upload, user_key: user_key, kind: "ohlife")
      }.to raise_error(ImportUploadStore::Error, /Only \.zip/)
    end

    it "does not use the client-supplied filename on disk" do
      upload = uploaded_file(
        filename: "../../../etc/passwd.json",
        content_type: "application/json",
        tempfile: tempfile
      )

      path = described_class.store!(uploaded_file: upload, user_key: user_key, kind: "trailmix")

      expect(path).not_to include("etc/passwd")
      expect(File.basename(File.dirname(path))).to match(/\A[0-9a-f-]{36}\z/)
    end
  end

  describe ".cleanup!" do
    it "removes the upload directory under tmp/imports" do
      upload = uploaded_file(filename: "entries.json", content_type: "application/json", tempfile: tempfile)
      path = described_class.store!(uploaded_file: upload, user_key: user_key, kind: "trailmix")
      dir = File.dirname(path)

      described_class.cleanup!(path)

      expect(File.exist?(dir)).to eq(false)
    end

    it "refuses to delete paths outside the imports base dir" do
      outside = File.join(tmpdir, "keep-me")
      FileUtils.mkdir_p(outside)
      File.write(File.join(outside, "file.txt"), "x")

      described_class.cleanup!(File.join(outside, "file.txt"))

      expect(File.exist?(outside)).to eq(true)
    end
  end
end
