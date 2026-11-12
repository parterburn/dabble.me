# frozen_string_literal: true

require "fog/aws"

# Private storage for export ZIPs. Photos in the main bucket are public by
# design; exports must never be. They are stored with a private ACL under
# their own prefix (or in their own bucket, AWS_EXPORTS_BUCKET) and reached
# only through links that expire in minutes.
class ExportStore
  PREFIX = "exports"
  # Above this size, uploads are sent in parts.
  MULTIPART_CHUNK = 50.megabytes

  def self.key_for(export)
    environment = Rails.env.production? ? nil : Rails.env
    [PREFIX, environment, export.user_id, "#{SecureRandom.uuid}.zip"].compact.join("/")
  end

  def upload(key, path)
    File.open(path, "rb") do |file|
      directory.files.create(key: key, body: file, public: false, content_type: "application/zip",
                             multipart_chunk_size: MULTIPART_CHUNK)
    end
    key
  end

  # A link to the file that works until `expires_at` and downloads under
  # `filename`.
  def download_url(key, filename:, expires_at:)
    storage.get_object_https_url(
      bucket, key, expires_at,
      query: { "response-content-disposition" => %(attachment; filename="#{filename}"), "response-content-type" => "application/zip" }
    )
  end

  def delete(key)
    storage.delete_object(bucket, key)
    true
  rescue Excon::Error::NotFound
    true
  end

  def exist?(key)
    !directory.files.head(key).nil?
  end

  private

  def bucket
    ENV["AWS_EXPORTS_BUCKET"].presence || CarrierWave::Uploader::Base.fog_directory.presence || ENV["AWS_BUCKET"]
  end

  def directory
    storage.directories.new(key: bucket)
  end

  def storage
    @storage ||= Fog::Storage.new(CarrierWave::Uploader::Base.fog_credentials)
  end
end
