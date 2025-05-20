class UploadToS3
  def initialize(file_key:, body:)
    @file_key = file_key
    @body = body
  end

  def call
    directory = s3.directories.new(key: ENV["AWS_BUCKET"])
    directory.files.create(key: @file_key, body: @body, public: true, content_disposition: "inline", cache_control: "public, max-age=#{365.days.to_i}")
  end

  private

  def s3
    @s3 ||= Fog::Storage.new({
      provider:              "AWS",
      aws_access_key_id:     ENV["AWS_ACCESS_KEY_ID"],
      aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
    })
  end
end
