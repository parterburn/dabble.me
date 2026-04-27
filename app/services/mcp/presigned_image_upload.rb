# frozen_string_literal: true

require 'fog/aws'

module Mcp
  class PresignedImageUpload
    EXPIRES_IN = 15.minutes
    MAX_BYTES = 20.megabytes
    SAFE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp .heic .heif].freeze

    def initialize(user:)
      @user = user
    end

    def call(filename:, content_type:)
      content_type = normalized_content_type(content_type)
      unless allowed_content_type?(content_type)
        return { success: false, errors: ["content_type #{content_type.inspect} is not an allowed image type"] }
      end

      key = self.class.build_key(user: @user, filename: filename, content_type: content_type)
      expires_at = EXPIRES_IN.from_now
      headers = upload_headers(content_type)

      {
        success: true,
        upload_method: 'PUT',
        upload_url: storage.put_object_url(bucket_name, key, expires_at, headers),
        upload_headers: headers,
        uploaded_image_key: key,
        expires_at: expires_at.iso8601,
        max_bytes: MAX_BYTES
      }
    end

    def self.key_allowed_for_user?(user, key)
      key = key.to_s
      key.present? && key.start_with?(key_prefix_for(user)) && !key.include?('..')
    end

    def self.build_key(user:, filename:, content_type:)
      "#{key_prefix_for(user)}#{SecureRandom.uuid}#{extension_for(filename, content_type.to_s.downcase)}"
    end

    def self.key_prefix_for(user)
      add_dev = '/development' unless Rails.env.production?
      "uploads#{add_dev}/#{user.user_key}/mcp-temp/"
    end

    private

    def allowed_content_type?(content_type)
      Entry::ALLOWED_IMAGE_TYPES.any? { |allowed| content_type == allowed.downcase }
    end

    def bucket_name
      CarrierWave::Uploader::Base.fog_directory.presence || ENV['AWS_BUCKET']
    end

    def normalized_content_type(content_type)
      content_type.to_s.split(';').first&.strip&.downcase.to_s
    end

    def storage
      @storage ||= Fog::Storage.new(CarrierWave::Uploader::Base.fog_credentials)
    end

    def upload_headers(content_type)
      {
        'Content-Type' => content_type,
        'x-amz-acl' => 'public-read',
        'Content-Disposition' => 'inline',
        'Cache-Control' => "public, max-age=#{365.days.to_i}"
      }
    end

    def self.extension_for(filename, content_type)
      ext = File.extname(filename.to_s).downcase
      return ext if SAFE_EXTENSIONS.include?(ext)

      {
        'image/jpeg' => '.jpg',
        'image/jpg' => '.jpg',
        'image/png' => '.png',
        'image/gif' => '.gif',
        'image/webp' => '.webp',
        'image/heic' => '.heic',
        'image/heif' => '.heif',
        'image/heic-sequence' => '.heic',
        'image/heif-sequence' => '.heif'
      }.fetch(content_type, '.bin')
    end
  end
end
