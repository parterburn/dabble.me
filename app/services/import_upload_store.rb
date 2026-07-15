# frozen_string_literal: true

# Stores import uploads outside of public/ with server-generated names.
# Paths are under tmp/imports and are never web-served.
class ImportUploadStore
  BASE_DIR = Rails.root.join("tmp", "imports").freeze

  ALLOWED = {
    "ohlife" => {
      extensions: %w[.zip].freeze,
      content_types: %w[
        application/zip
        application/x-zip-compressed
        application/octet-stream
      ].freeze
    }.freeze,
    "trailmix" => {
      extensions: %w[.json].freeze,
      content_types: %w[
        application/json
        text/json
        text/plain
        application/octet-stream
      ].freeze
    }.freeze
  }.freeze

  class Error < StandardError; end

  def self.store!(uploaded_file:, user_key:, kind:)
    new(uploaded_file: uploaded_file, user_key: user_key, kind: kind).store!
  end

  def self.cleanup!(path)
    return if path.blank?

    upload_dir = Pathname.new(path).dirname
    return unless upload_dir.to_s.start_with?(BASE_DIR.to_s)

    FileUtils.rm_rf(upload_dir)
  end

  def initialize(uploaded_file:, user_key:, kind:)
    @uploaded_file = uploaded_file
    @user_key = user_key.to_s
    @kind = kind.to_s
  end

  def store!
    raise Error, "No file uploaded" if @uploaded_file.blank?
    raise Error, "Invalid import kind" unless ALLOWED.key?(@kind)
    raise Error, "Invalid user" if @user_key.blank? || @user_key.include?("..") || @user_key.include?("/")

    ext = File.extname(@uploaded_file.original_filename.to_s).downcase
    allowed = ALLOWED[@kind]
    unless allowed[:extensions].include?(ext)
      raise Error, "Only #{allowed[:extensions].join(', ')} files are allowed"
    end

    content_type = @uploaded_file.content_type.to_s.downcase
    unless content_type.blank? || allowed[:content_types].include?(content_type)
      raise Error, "Invalid file type"
    end

    upload_id = SecureRandom.uuid
    dir = BASE_DIR.join(@kind, @user_key, upload_id)
    FileUtils.mkdir_p(dir)
    path = dir.join("upload#{ext}")

    FileUtils.mv(@uploaded_file.tempfile.path, path)
    File.chmod(0o600, path)

    path.to_s
  end
end
