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
    entry.update(filepicker_url: nil)
    entry.remote_image_url = filestack_collage_url
    entry.save
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
      next unless att["size"].to_i > 20_000

      att["url"].gsub("://", "://api:#{ENV['MAILGUN_API_KEY']}@")
    end.compact
    return nil unless attachment_urls.any?

    collage_from_urls(attachment_urls + [@existing_url])
  end

  def collage_from_urls(urls)
    return nil unless urls.present?

    urls.reject! { |url| url&.include?("googleusercontent.com/mail-sig/") }
    urls.compact!

    if urls.size == 1 && urls.first.starts_with?("http")
      urls.first
    elsif urls.any?
      first_url = urls.first.include?("%40") ? urls.first : CGI.escape(urls.first) # don't escape if already escaped
      "https://process.filestackapi.com/#{ENV['FILESTACK_API_KEY']}/collage=a:true,i:auto,f:[#{urls[1..-1].map(&:inspect).join(',')}],w:1200,h:1200,m:1/#{first_url}"
    end
  end
end
