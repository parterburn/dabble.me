class ImageCollageJob < ActiveJob::Base
  queue_as :default

  def perform(entry_id, urls: nil, message_id: nil)
    entry = Entry.where(id: entry_id).first
    return nil unless entry.present?

    @message_id = message_id
    @user = entry.user

    entry.update(filepicker_url: "https://d10r8m94hrfowu.cloudfront.net/uploading.png")
    @existing_url = entry&.image_url_cdn == "https://d10r8m94hrfowu.cloudfront.net/uploading.png" ? nil : entry&.image_url_cdn

    if @message_id.present?
      filestack_collage_url = collage_from_mailgun_attachments
    else
      filestack_collage_url = collage_from_urls(urls + [@existing_url])
    end

    entry.remote_image_url = filestack_collage_url
    unless entry.save && FastImage.type(filestack_collage_url).present?
      Sentry.set_user(id: @user.id, email: @user.email)
      Sentry.capture_message("Error updating collage image", level: :info, extra: { entry_id: entry_id, error: entry.errors.full_messages, filestack_collage_url: filestack_collage_url, fastimage_type: FastImage.type(filestack_collage_url) })

      EntryMailer.image_error(@user, entry, filestack_collage_url).deliver_later
    end
    entry.update(filepicker_url: nil) if entry.filepicker_url == "https://d10r8m94hrfowu.cloudfront.net/uploading.png"
  end

  def collage_from_mailgun_attachments
    return unless @message_id.present?

    last_message = nil
    message = nil
    5.times do
      connection = Faraday.new(url: "https://api.mailgun.net") do |f|
        f.request :json
        f.response :json
        f.request :authorization, :basic, 'api', ENV['MAILGUN_API_KEY']
        f.options.timeout = 120
        f.options.open_timeout = 120
      end
      resp = connection.get("/v3/#{ENV['SMTP_DOMAIN']}/events?pretty=yes&event=accepted&ascending=no&limit=1&message-id=#{@message_id}")
      last_message = resp.body&.dig("items", 0) if resp.success?
      break if last_message.present?
      sleep 10
    end
    return unless last_message.present?

    message = nil
    5.times do
      message_url = URI.parse(last_message["storage"]["url"])
      msg_conn = Faraday.new("https://#{message_url.host}") do |f|
        f.options.timeout = 120
        f.options.open_timeout = 120
        f.request :json
        f.response :json
        f.request :authorization, :basic, 'api', ENV['MAILGUN_API_KEY']
      end
      response = msg_conn.get(message_url.path)
      message = response.body if response.success?
      break if message.present?
      sleep 10
    end
    return unless message.present? && message["recipients"].to_s.include?(@user.user_key) || message["from"].to_s.include?(@user.email)

    attachment_urls = message["attachments"].map do |att|
      next unless Entry::ALLOWED_IMAGE_TYPES.include?(att["content-type"]&.downcase)
      next unless att["size"].to_i > 20_000 # ignore tiny attachments

      "#{att["url"].gsub("://", "://api:#{ENV['MAILGUN_API_KEY']}@")}?#{att["name"]}"
    end.compact_blank

    return nil unless attachment_urls.any?

    collage_from_urls(attachment_urls + [@existing_url])
  end

  def collage_from_urls(urls)
    return nil unless urls.present?

    urls.reject! { |url| url.is_a?(String) && url&.include?("googleusercontent.com/mail-sig/") }

    urls = urls.map do |url|
      next if url.blank?

      if url.downcase.ends_with?(".heic")
        begin
          if url.include?("@")
            uri = URI.parse(url)
            conn = Faraday.new(uri.scheme + "://" + uri.host) do |f|
              f.options.timeout = 120
              f.options.open_timeout = 120
              f.request :authorization, :basic, "api", ENV['MAILGUN_API_KEY']
            end
            response = conn.get(uri.path)
            tempfile = Tempfile.new(['attachment', ".heic"])
            tempfile.binmode
            tempfile.write(response.body)
            tempfile.rewind
            result = ImageConverter.new(tempfile: tempfile, width: 1200, user: @user).s3_url
            tempfile.close
            tempfile.unlink
            result
          else
            file = URI.parse(url).open
            ImageConverter.new(tempfile: file, width: 1200, user: @user).s3_url
          end
        rescue => e
          Sentry.capture_exception(e)
          nil
        end
      else
        url
      end
    end.compact_blank

    if urls.size == 1 && urls.first.starts_with?("http")
      urls.first
    elsif urls.any?
      first_url = urls.first.include?("%") ? urls.first : CGI.escape(urls.first) # don't escape if already contains escape sequences

      remaining_urls = urls[1..-1].map do |url|
        url.include?("%") ? url : CGI.escape(url)
      end.map(&:inspect).join(',')

      url = "https://process.filestackapi.com/#{ENV['FILESTACK_API_KEY']}/collage=a:true,i:auto,f:%5B#{remaining_urls}%5D,w:1200,h:1200,m:1/#{first_url}"
      url
    end
  end
end
