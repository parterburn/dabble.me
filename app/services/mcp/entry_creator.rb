# frozen_string_literal: true

require 'base64'
require 'image_processing/vips'
require 'ipaddr'
require 'net/http'
require 'resolv'
require 'uri'

module Mcp
  class EntryCreator
    MAX_IMAGE_BYTES = 20.megabytes
    BASE64_IMAGE_MAX_DIMENSION = 800
    HTTP_OPEN_TIMEOUT = 15
    HTTP_READ_TIMEOUT = 60
    MAX_REDIRECTS = 5

    MIME_TO_EXT = {
      'image/jpeg' => '.jpg',
      'image/jpg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'image/heic' => '.heic',
      'image/heif' => '.heif',
      'application/octet-stream' => '.bin'
    }.freeze

    BASE64_RESIZE_OUTPUT_TYPES = {
      'image/jpeg' => 'jpg',
      'image/jpg' => 'jpg',
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      'application/octet-stream' => 'jpg'
    }.freeze

    def initialize(user:)
      @user = user
    end

    # Creates an entry for the given calendar day, or appends to that day's entry when
    # merge_with_existing is true (same behavior as the web "add to this day" flow).
    #
    # Optional image (only one):
    # - image_url: https URL to an image (fetched server-side; blocks loopback/private hosts).
    # - uploaded_image_key: key returned by get_image_upload_url after the client uploads directly.
    # - image_base64: raw base64 or a data URL (data:image/png;base64,...). Callers should
    #   resize to fit within 800x800 before encoding; the server enforces that limit too.
    #   With raw base64, pass image_mime_type (e.g. image/png) or it defaults to image/jpeg.
    def create(date_string:, body_text:, merge_with_existing: true, image_url: nil, image_base64: nil, image_mime_type: nil, uploaded_image_key: nil)
      date = parse_date(date_string)
      return date if date.is_a?(Hash)

      uploaded_key = uploaded_image_key.to_s.strip.presence
      image_upload = resolve_image_upload(
        image_url: image_url,
        image_base64: image_base64,
        image_mime_type: image_mime_type,
        uploaded_image_key: uploaded_key
      )
      return image_upload if image_upload.is_a?(Hash) && image_upload[:success] == false

      plain = body_text.to_s.strip
      has_image_input = image_upload.present? || uploaded_key.present?
      if plain.blank? && !has_image_input
        return { success: false, errors: ['Body cannot be blank unless an image is provided'] }
      end

      html_body = if plain.present?
        format_plain_body(plain)
      elsif has_image_input
        '<p></p>'
      else
        ''
      end
      existing = find_entry_on_calendar_day(date)

      if existing.present?
        if existing.image.present? && has_image_input
          return {
            success: false,
            errors: ['This day already has an image. Omit image_url / image_base64 / uploaded_image_key when merging, or use a day without a photo.']
          }
        end

        if merge_with_existing
          existing.body = plain.present? ? "#{existing.body}<hr>#{html_body}" : existing.body
          assign_entry_image!(existing, image_upload)
          return persist(existing, merged: true, uploaded_image_key: uploaded_key)
        end

        return {
          success: false,
          errors: [
            "An entry already exists for #{date.iso8601}. Pass merge_with_existing: true to append, or choose another date."
          ]
        }
      end

      entry = @user.entries.build(date: calendar_day_start(date), body: html_body)
      assign_entry_image!(entry, image_upload)
      persist(entry, merged: false, uploaded_image_key: uploaded_key)
    end

    private

    def assign_entry_image!(entry, image_upload)
      return if image_upload.blank?

      entry.image = image_upload
    end

    def resolve_image_upload(image_url:, image_base64:, image_mime_type:, uploaded_image_key:)
      url = image_url.to_s.strip.presence
      b64 = image_base64.to_s.strip.presence
      uploaded_key = uploaded_image_key.to_s.strip.presence

      if [url, b64, uploaded_key].compact.size > 1
        return { success: false, errors: ['Provide only one of image_url, image_base64, or uploaded_image_key'] }
      end

      if uploaded_key
        unless Mcp::PresignedImageUpload.key_allowed_for_user?(@user, uploaded_key)
          return { success: false, errors: ['uploaded_image_key is not valid for this account'] }
        end

        return nil
      end

      if url
        return fetch_image_upload_from_url(url)
      end

      return nil if b64.blank?

      decode_image_upload_from_base64(b64, image_mime_type)
    end

    def fetch_image_upload_from_url(url_string)
      uri = parse_public_http_uri(url_string)
      return uri if uri.is_a?(Hash)

      unless safe_fetch_host?(uri)
        return { success: false, errors: ['image_url host is not allowed (private or unresolved host)'] }
      end

      downloaded = http_download_image(uri)
      return downloaded if downloaded.is_a?(Hash)

      body, content_type, filename_hint = downloaded
      content_type = infer_image_content_type(body, content_type)

      unless acceptable_image_content_type?(content_type)
        return {
          success: false,
          errors: ["URL did not return an allowed image type (got #{content_type.inspect})"]
        }
      end

      ext = extension_for(content_type, filename_hint)
      build_upload(body, "mcp-image#{ext}", content_type_for_store(content_type))
    rescue StandardError => e
      Rails.logger.warn("[Mcp::EntryCreator] image_url fetch failed: #{e.class}: #{e.message}")
      { success: false, errors: ["Could not download image from URL: #{e.message}"] }
    end

    def decode_image_upload_from_base64(raw, mime_hint)
      parsed = parse_base64_image(raw, mime_hint)
      return parsed if parsed.is_a?(Hash)

      mime, bytes = parsed

      if bytes.blank?
        return { success: false, errors: ['image_base64 decoded to empty data'] }
      end

      if bytes.bytesize > MAX_IMAGE_BYTES
        return { success: false, errors: ["Image is too large (max #{MAX_IMAGE_BYTES / 1.megabyte} MB)"] }
      end

      unless acceptable_image_content_type?(mime)
        return { success: false, errors: ["image_mime_type #{mime.inspect} is not an allowed image type"] }
      end

      bytes, mime = resize_base64_image(bytes, mime)
      ext = extension_for(mime, nil)
      build_upload(bytes, "mcp-image#{ext}", content_type_for_store(mime))
    rescue ArgumentError, OpenSSL::SSL::SSLError => e
      { success: false, errors: ["Invalid image_base64: #{e.message}"] }
    end

    def parse_base64_image(value, mime_hint)
      s = value.to_s.strip
      return { success: false, errors: ['image_base64 is blank'] } if s.blank?

      if (m = s.match(/\Adata:([\w.+\/-]+);base64,(.*)\z/m))
        mime = m[1].downcase
        raw = Base64.decode64(m[2].gsub(/\s+/, ''))
        [mime, raw]
      else
        mime = mime_hint.to_s.strip.downcase.presence || 'image/jpeg'
        [mime, Base64.decode64(s.gsub(/\s+/, ''))]
      end
    end

    def build_upload(bytes, filename, content_type)
      tmp = Tempfile.new(['mcp-entry-image', File.extname(filename)])
      tmp.binmode
      tmp.write(bytes)
      tmp.rewind
      ActionDispatch::Http::UploadedFile.new(
        tempfile: tmp,
        filename: File.basename(filename),
        type: content_type
      )
    end

    def resize_base64_image(bytes, mime)
      input = Tempfile.new(['mcp-base64-image', extension_for(mime, nil)])
      input.binmode
      input.write(bytes)
      input.rewind

      content_type = content_type_for_store(mime)
      output_type = BASE64_RESIZE_OUTPUT_TYPES.fetch(content_type, 'jpg')
      output_content_type = content_type == 'application/octet-stream' ? 'image/jpeg' : content_type
      processed = ImageProcessing::Vips
                  .source(input)
                  .resize_to_limit(BASE64_IMAGE_MAX_DIMENSION, BASE64_IMAGE_MAX_DIMENSION)
                  .convert(output_type)
                  .call
      processed.binmode
      processed.rewind
      [processed.read, output_content_type]
    rescue StandardError => e
      Rails.logger.warn("[Mcp::EntryCreator] image_base64 resize failed: #{e.class}: #{e.message}")
      raise ArgumentError, "could not resize image to #{BASE64_IMAGE_MAX_DIMENSION}x#{BASE64_IMAGE_MAX_DIMENSION}"
    ensure
      processed&.close
      processed&.unlink
      input&.close
      input&.unlink
    end

    def parse_public_http_uri(url_string)
      uri = URI.parse(url_string)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return { success: false, errors: ['image_url must be http or https'] }
      end
      return { success: false, errors: ['image_url may not contain embedded credentials'] } if uri.userinfo.present?
      return { success: false, errors: ['image_url must use https in production'] } if Rails.env.production? && !uri.is_a?(URI::HTTPS)

      uri
    rescue URI::InvalidURIError
      { success: false, errors: ['image_url is not a valid URL'] }
    end

    def safe_fetch_host?(uri)
      host = uri.host.to_s.downcase
      return false if host.blank?
      return false if blocked_hostname?(host)

      addrs = Resolv.getaddresses(host)
      return false if addrs.empty?

      addrs.all? { |ip| public_ip?(ip) }
    rescue Resolv::ResolvError, IPAddr::InvalidAddressError
      false
    end

    def blocked_hostname?(host)
      return true if host == 'localhost'
      return true if host.end_with?('.local')
      return true if host == 'metadata.google.internal'

      false
    end

    def public_ip?(ip)
      addr = IPAddr.new(ip)
      return false if addr.loopback?
      return false if addr.private?
      return false if addr.ipv4? && addr.to_s.start_with?('169.254.')
      if addr.ipv6?
        return false if addr.to_s.match?(/\Afe80:/i)
        return false if addr.to_s.match?(/\Afc00:/i) || addr.to_s.match?(/\Afd[0-9a-f]{2}:/i)
      end

      true
    rescue IPAddr::InvalidAddressError
      false
    end

    def http_download_image(uri, redirects_left = MAX_REDIRECTS)
      return { success: false, errors: ['Too many redirects when fetching image_url'] } if redirects_left.negative?

      unless safe_fetch_host?(uri)
        return { success: false, errors: ['Redirect target host is not allowed'] }
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.is_a?(URI::HTTPS)
      http.open_timeout = HTTP_OPEN_TIMEOUT
      http.read_timeout = HTTP_READ_TIMEOUT

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      case response
      when Net::HTTPSuccess
        body = response.body.to_s
        if body.bytesize > MAX_IMAGE_BYTES
          return { success: false, errors: ["Image from URL is too large (max #{MAX_IMAGE_BYTES / 1.megabyte} MB)"] }
        end

        ct = response['content-type'].to_s.split(';').first&.strip
        [body, ct, File.basename(uri.path)]
      when Net::HTTPRedirection
        location = response['location'].to_s
        return { success: false, errors: ['Redirect location missing'] } if location.blank?

        next_uri = URI.join(uri.to_s, location)
        http_download_image(next_uri, redirects_left - 1)
      else
        { success: false, errors: ["image_url HTTP #{response.code}"] }
      end
    end

    def acceptable_image_content_type?(content_type)
      ct = content_type.to_s.downcase.strip
      return true if ct.blank?

      Entry::ALLOWED_IMAGE_TYPES.any? { |allowed| ct == allowed.downcase }
    end

    def content_type_for_store(content_type)
      ct = content_type.to_s.split(';').first&.strip.downcase
      return 'application/octet-stream' if ct.blank?

      ct
    end

    def extension_for(content_type, filename_hint)
      ct = content_type.to_s.split(';').first&.strip.downcase
      if ct.present? && MIME_TO_EXT[ct]
        MIME_TO_EXT[ct]
      elsif filename_hint.present?
        ext = File.extname(filename_hint.to_s)
        return ext if ext.match?(/\A\.[a-z0-9]{2,5}\z/i)
      end

      '.jpg'
    end

    # Entries store a datetime; match the user's calendar day (same idea as date-range filters elsewhere).
    def find_entry_on_calendar_day(date)
      day_start = calendar_day_start(date)
      @user.entries.where(date: day_start..day_start.end_of_day).first
    end

    def calendar_day_start(date)
      tz = ActiveSupport::TimeZone[@user.send_timezone] || Time.zone
      tz.local(date.year, date.month, date.day).beginning_of_day
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      { success: false, errors: ["Invalid date #{value.inspect}. Use YYYY-MM-DD."] }
    end

    def format_plain_body(plain)
      escaped = ERB::Util.html_escape(plain)
      ActionController::Base.helpers.simple_format(escaped, {}, sanitize: false)
    end

    def persist(entry, merged:, uploaded_image_key: nil)
      entry.uploading_image = true if uploaded_image_key.present?

      if entry.save
        ProcessEntryImageJob.perform_later(entry.id, uploaded_image_key) if uploaded_image_key.present?
        { success: true, merged: merged, entry: serialize(entry) }
      else
        { success: false, errors: entry.errors.full_messages }
      end
    end

    def infer_image_content_type(body, header_type)
      ct = header_type.to_s.split(';').first&.strip
      return ct if ct.present?

      ft = FastImage.type(StringIO.new(body))
      return "image/#{ft}" if ft.present?

      ''
    end

    def serialize(entry)
      {
        id: entry.id,
        date: entry.date.to_date.iso8601,
        url: Tools::Helpers.entry_public_url(entry),
        excerpt: entry.text_body.to_s.squish.truncate(5000),
        hashtags: entry.hashtags,
        has_image: entry.image.present?,
        image_processing: entry.uploading_image?
      }
    end
  end
end
