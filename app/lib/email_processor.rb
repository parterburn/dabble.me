# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/ClassLength
# rubocop:disable Metrics/PerceivedComplexity
# rubocop:disable Metrics/CyclomaticComplexity
require 'fileutils'

# Handle Emailed Entries
class EmailProcessor
  def initialize(email)
    @token = pick_meaningful_recipient(email.to, email.cc)
    @from = email.from[:email].downcase
    @to = email.to
    @cc = email.cc
    @bcc = email.bcc
    @subject = to_utf8(email.subject)
    @stripped_html = email.vendor_specific.try(:[], :stripped_html)
    @body = clean_message(email.body).presence || "No entry provided."

    @html = clean_html_version(@stripped_html)
    @message_id = email.headers&.dig("Message-ID")&.gsub("<", "")&.gsub(">", "")

    @raw_body = to_utf8(email.raw_body)
    @attachments = email.attachments
    @user = find_user_from_user_key(@token, @from)

    @inbound_email_params = {
      subject:     to_utf8(email.subject),
      cc:          email.cc,
      bcc:         email.bcc,
      spam_report: email.spam_report,
      headers:     email.headers,
      charsets:    email.charsets,
      stripped_html: @stripped_html
    }
  end

  def process
    if @user.present?
      Sentry.set_user(id: @user.id, email: @user.email)
      Sentry.set_tags(plan: @user.plan)

      best_attachment = nil
      best_attachment_url = nil
      if @user.is_pro? && @attachments.present?
        valid_attachments = []
        @attachments.each do |attachment|
          next unless attachment.present?

          # Make sure attachments are at least 20kb so we're not saving a bunch of signature/footer images\
          file_size = File.size?(attachment.tempfile).to_i

          # skip signature images
          next if @user.id == 293 && attachment&.original_filename.to_s.downcase.include?("cropped-img-0719-300x86.jpeg")
          next if @user.id == 10836 && attachment&.original_filename.to_s.downcase.include?("b_logo.png")
          next if @user.id == 2541 && attachment&.original_filename.to_s.downcase.include?("image001.jpg")
          next if @user.id == 20829 && attachment.content_type == "application/octet-stream"

          next if attachment&.original_filename.to_s.downcase.include?("linkedin_icon_circle.svg.png")

          if (attachment.content_type == "application/octet-stream" || attachment.content_type =~ /^image\/(png|jpe?g|webp|gif|heic|heif)$/i || attachment&.original_filename.to_s =~ /^(.+\.(heic|heif))$/i) && file_size > 20000
            valid_attachments << attachment
          end
        end

        if valid_attachments.size > 1
          best_attachment_url = "mailgun_collage:#{@message_id}"
        elsif valid_attachments.any?
          best_attachment = valid_attachments.first
        end
      end

      # If image came in as a URL, try saving that
      if best_attachment_url.blank? && best_attachment.blank? && @stripped_html.present?
        email_reply_html = @stripped_html&.split(/reply to this email with your /i)&.first
        image_urls = email_reply_html&.scan(/<img\s.*?src=(?:'|")([^'">]+)(?:'|")/i)
        image_urls.flatten! if image_urls.present?
        if @user.is_pro? && image_urls.present? && image_urls.any?
          valid_attachment_urls = []
          image_urls.each do |image_url|
            image_type = FastImage.type(image_url)

            if image_type.in?([:gif, :jpeg, :png])
              image_width, image_height = FastImage.size(image_url)
              next if image_height && image_width && image_height < 100 && image_width < 100

              # skip signature images
              next if image_url.downcase.include?("googleusercontent.com/mail-sig/")
              next if @user.id == 293 && image_url.downcase.include?("cropped-img-0719-300x86.jpeg")
              next if @user.id == 10836 && image_url.downcase.include?("b_logo.png")
              next if @user.id == 2541 && image_url.downcase.include?("image001.jpg")
              next if image_url.downcase.include?("linkedin_icon_circle.svg.png")
              next if image_url.downcase.include?("app.v1ce.co.uk") # digital business cards

              valid_attachment_urls << image_url
            end
          end

          if valid_attachment_urls.size > 1
            best_attachment_url = collage_from_urls(valid_attachment_urls.first(7))
          elsif valid_attachment_urls.any?
            best_attachment_url = valid_attachment_urls.first
          end
        end
      end

      date = parse_subject_for_date(@subject)
      existing_entry = @user.existing_entry(date.to_s)
      inspiration_id = parse_body_for_inspiration_id(@raw_body)
      @body = @html.presence if @html.present? && @user.is_pro?

      if existing_entry.present?
        existing_entry.original_email = @inbound_email_params

        if respond_as_ai? && existing_entry.body.present?
          existing_entry.body += "<hr><strong>👤 You:</strong><br/>#{@body}"
        elsif existing_entry.body.present?
          existing_entry.body += "<hr>#{@body}"
        else
          existing_entry.body = @body
        end

        existing_entry.body = existing_entry.sanitized_body if @user.is_free?
        existing_entry.original_email_body = @raw_body
        existing_entry.inspiration_id = inspiration_id if inspiration_id.present?
        existing_entry.save
        if existing_entry.image_url_cdn.blank?
          if best_attachment.present?
            existing_entry.update(filepicker_url: "https://d10r8m94hrfowu.cloudfront.net/uploading.png")
            ProcessEntryImageJob.perform_later(
              existing_entry.id,
              attachment_data: {
                content_type: best_attachment.content_type,
                original_filename: best_attachment.original_filename,
                data: Base64.strict_encode64(File.read(best_attachment.tempfile))
              }
            )
          elsif best_attachment_url.present? && best_attachment_url.starts_with?("mailgun_collage:")
            ImageCollageJob.perform_later(existing_entry.id, message_id: best_attachment_url.gsub("mailgun_collage:", ""))
          elsif best_attachment_url.present?
            existing_entry.remote_image_url = best_attachment_url
          end
        elsif existing_entry.image_url_cdn.present?
          if best_attachment.present?
            image_urls = collage_from_attachments([best_attachment])
            ImageCollageJob.perform_later(existing_entry.id, urls: image_urls)
          elsif best_attachment_url.present?
            existing_entry.update(filepicker_url: "https://d10r8m94hrfowu.cloudfront.net/uploading.png")
            existing_image = existing_entry.image_url_cdn == "https://d10r8m94hrfowu.cloudfront.net/uploading.png" ? nil : existing_entry.image_url_cdn
            existing_entry.remote_image_url = collage_from_urls([best_attachment_url, existing_image])
            existing_entry.filepicker_url = nil
          end
        end

        if existing_entry.save
          track_ga_event('Merged')

          if respond_as_ai? && @user && @user.can_ai?
            AiEntryJob.perform_later(@user.id, existing_entry.id)
          end
        else
          # error saving entry
          Sentry.capture_message("Error processing entry via email", level: :error, extra: { reason: "Could not save existing entry", subject: @subject, entry_id: existing_entry&.id, errors: existing_entry&.errors&.full_messages })
          UserMailer.failed_entry(@user, existing_entry.errors.full_messages.to_sentence, date, @body).deliver_later
          raise "Failed entry" # for mailgun to retry
        end
      else
        begin
          params = { date: date, inspiration_id: inspiration_id, body: @body, original_email_body: @raw_body }
          entry = @user.entries.create!(params)
          entry.save
          if best_attachment.present?
            entry.update(filepicker_url: "https://d10r8m94hrfowu.cloudfront.net/uploading.png")
            ProcessEntryImageJob.perform_later(
              entry.id,
              attachment_data: {
                content_type: best_attachment.content_type,
                original_filename: best_attachment.original_filename,
                data: Base64.strict_encode64(File.read(best_attachment.tempfile))
              }
            )
          elsif best_attachment_url.present? && best_attachment_url.starts_with?("mailgun_collage:")
            ImageCollageJob.perform_later(entry.id, message_id: best_attachment_url.gsub("mailgun_collage:", ""))
          elsif best_attachment_url.present?
            entry.update(filepicker_url: "https://d10r8m94hrfowu.cloudfront.net/uploading.png")
            entry.remote_image_url = best_attachment_url
            entry.filepicker_url = nil
            entry.save
          end
        rescue ActiveRecord::RecordInvalid => error
          @error = error
          if error.to_s.include?("Image Failed to manipulate with MiniMagick")
            entry = @user.entries.create!(params.except(:image, :remote_image_url).merge(body: @body, original_email_body: @raw_body))
            Sentry.capture_message("Error processing image via email", level: :error, extra: { reason: "Image Failed to manipulate with MiniMagick", error: error, image: best_attachment, remote_image_url: best_attachment_url, subject: @subject, entry: entry })
          else
            Sentry.capture_message("Error processing entry via email", level: :error, extra: { reason: "ActiveRecord::RecordInvalid", error: error, subject: @subject })
          end
        rescue => error
          @error = error
          Sentry.capture_message("Error processing entry via email", level: :error, extra: { error: error, subject: @subject, body: @body, raw_body: @raw_body })
          @body = @body.force_encoding('iso-8859-1').encode('utf-8')
          @raw_body = @raw_body.force_encoding('iso-8859-1').encode('utf-8')
          entry = @user.entries.create!(params.merge(body: @body, original_email_body: @raw_body))
        end
        entry&.original_email = @inbound_email_params
        entry&.body = entry&.sanitized_body if @user.is_free?
        if entry&.save
          track_ga_event('New')
        else
          if entry.present?
            record_errors = entry.errors.full_messages.to_sentence
          else
            record_errors = @error.full_messages.to_sentence
          end
          Sentry.capture_message("Error processing entry via email", level: :error, extra: { reason: "Could not save new entry (failed_entry email sent to hello@dabble.me)", errors: entry&.errors&.full_messages, rescue_error: @error, body: @body, date: date })
          UserMailer.failed_entry(@user, record_errors, date, @body).deliver_later
          raise "Failed entry" # for mailgun to retry
        end
      end

      @user.increment!(:emails_received)
      begin
        UserMailer.second_welcome_email(@user).deliver_later if @user.emails_received == 1 && @user.entries.count == 1
      rescue StandardError => e
        Sentry.capture_message("Error sending email", level: :error, extra: { email_type: "Second Welcome Email" })
      end

      if entry.present? && respond_as_ai? && @user && @user.can_ai?
        AiEntryJob.perform_later(@user.id, entry.id)
      end
    else # no user found
      Sentry.set_user(id: @token, email: @from)
      Sentry.capture_message("Inbound entry not associated to user", level: :error, extra: { subject: @subject, body: @body, html: @html, raw_body: @raw_body })
    end
  end

  private

  attr_reader :to, :cc, :bcc

  def all_recipients
    (to.to_a + cc.to_a + bcc.to_a)
  end

  def respond_as_ai?
    all_recipients.select { |k| k[:host] == ENV['SMTP_DOMAIN'].gsub('post', 'ai') }.any?
  end

  def track_ga_event(action)
    if ENV['GOOGLE_ANALYTICS_ID'].present?
      # tracker = Staccato.tracker(ENV['GOOGLE_ANALYTICS_ID'])
      # tracker.event(category: 'Email Entry', action: action, label: @user.user_key)
    end
  end

  def pick_meaningful_recipient(to_recipients, cc_recipients)
    host_to = to_recipients.select {|k| k[:host] =~ /^(email|post|ai)?\.?#{ENV['MAIN_DOMAIN'].gsub(".","\.")}$/i }.first
    if host_to.present?
      host_to[:token]
    elsif cc_recipients.present?
      # try CC's
      host_cc = cc_recipients.select {|k| k[:host] =~ /^(email|post|ai)?\.?#{ENV['MAIN_DOMAIN'].gsub(".","\.")}$/i }.first
      host_cc[:token] if host_cc.present?
    end
  end

  def find_user_from_user_key(to_token, from_email)
    begin
      User.where(user_key: to_token).or(User.where(email: from_email)).first
    rescue JSON::ParserError => e
    end
  end

  def parse_subject_for_date(subject)
    # Find the date from the subject "It's Sept 2. How was your day?" and figure out the best year
    now = Time.now.in_time_zone(@user.send_timezone)
    parsed_date = Time.parse(subject) rescue now
    dates = [parsed_date, parsed_date.prev_year]
    dates_to_use = []
    dates.each do |d|
      dates_to_use << d if Time.now + 7.days - d > 0
    end
    if dates_to_use.blank?
      now.strftime('%Y-%m-%d')
    else
      dates_to_use.min_by { |d| (d - now).abs }.strftime('%Y-%m-%d')
    end
  end

  def unfold_paragraphs(body)
    return nil unless body.present?
    text  = ''
    body.split(/\n/).each do |line|
      if /\S/ !~ line
        text << "\n\n"
      else
        if line.length < 60 || /^(\s+|[*])/ =~ line
          text << (line.rstrip + "\n")
        else
          text << (line.rstrip + ' ')
        end
      end
    end
    text.gsub("\n\n\n", "\n\n")
  end

  def parse_body_for_inspiration_id(raw_body)
    inspiration_id = nil
    begin
      inspiration_id = Inspiration.without_imports_or_email_or_tips.select {|i| raw_body.downcase.include? i.body.first(71).downcase }.first&.id
    rescue
    end
    inspiration_id
  end

  def clean_message(body)
    return nil unless body.present?

    body = EmailReplyTrimmer.trim(body)

    body&.gsub!(/src=\"data\:image\/(jpeg|png)\;base64\,.*\"/, "src=\"\"") # remove embedded images
    body&.gsub!(/url\(data\:image\/(jpeg|png)\;base64\,.*\)/, "url()") # remove embedded images
    body&.gsub!(/\n\n\n/, "\n\n \n\n") # allow double line breaks
    body = unfold_paragraphs(body) unless @from.include?('yahoo.com') # fix wrapped plain text, but yahoo messes this up
    body&.gsub!(/\[image\:\ Inline\ image\ [0-9]{1,2}\]/, "(see attached image)") # remove "Inline image" text from griddler
    body&.gsub!(/(?:\n\r?|\r\n?)/, "<br>") # convert line breaks
    body&.gsub!(/(?:\n\n?|\n\n?)/, "<br><br>") # convert line breaks for iOS Mail
    body = "<p>#{body}</p>" # basic formatting
    body&.gsub!(/<(http[s]?:\/\/\S*?)>/, "(\\1)") # convert links to show up
    body&.gsub!(/<br\s*\/?>$/, "")&.gsub!(/<br\s*\/?>$/, "")&.gsub!(/^$\n/, "") # remove last unnecessary line break
    body&.gsub!(/--( \*)?$\z/, "") # remove gmail signature break
    body&.gsub!(/<style(?:\s+[^>]*)?>.*?<\/style>/mi, '') # remove styles
    body&.gsub!(/<xml(?:\s+[^>]*)?>.*?<\/xml>/mi, '') # remove xml

    body&.gsub!(/<!--.*?-->/m, '') # remove comments
    body&.gsub!('<![endif]-->', '') # remove comments
    body&.gsub!(/<br\s*\/?>\z/, "")&.gsub!(/<br\s*\/?>\z/, "")&.gsub!(/^$\n\z/, "") # remove last unnecessary line break
    body&.gsub!(/<br\s*\/?>\z/, "")&.gsub!(/<br\s*\/?>\z/, "")&.gsub!(/^$\n\z/, "") # remove last unnecessary line break
    body&.gsub!(/<br\s*\/?>\z/, "")&.gsub!(/<br\s*\/?>\z/, "")&.gsub!(/^$\n\z/, "") # remove last unnecessary line break
    body&.gsub!(/<br\s*\/?>\z/, "")&.gsub!(/<br\s*\/?>\z/, "")&.gsub!(/^$\n\z/, "") # remove last unnecessary line break
    body&.gsub!(/\A(\s*<br\s*\/?>|\s*<p>\s*<\/p>|\s*<div>\s*<\/div>|\s*\n|\s*\r\n)*/, '') # remove beginning line breaks

    body&.gsub!("p.MsoNormal,p.MsoNoSpacing{margin:0}", "") # remove outlook styles
    body = body&.strip

    return unless body.present?

    to_utf8(body)
  end

  def to_utf8(content)
    return unless content.present?
    content.gsub!("\0", "") # remove null characters
    begin
      detection = CharlockHolmes::EncodingDetector.detect(content)
      if detection[:confidence] > 95
        content = CharlockHolmes::Converter.convert content, detection[:encoding].gsub("IBM424_ltr", "UTF-8"), "UTF-8"
      end
    rescue
    end

    content
  end

  def clean_html_version(html)
    return nil unless html.present?

    html = EmailReplyTrimmer.trim(html)

    return unless html.present?

    html&.gsub!("<html>", "")&.gsub!("</html>", "")&.gsub!("<body>", "")&.gsub!("</body>", "")&.gsub!("<head>", "")&.gsub!("</head>", "")

    html = Rinku.auto_link(html, :all, 'target="_blank"')
    html = html.split("<br id=\"lineBreakAtBeginningOfSignature\">").first # strip out gmail signature
    html = html.split('<br id=\"lineBreakAtBeginningOfSignature\">').first # strip out gmail signature
    html = html.split('<br id="lineBreakAtBeginningOfSignature">').first # strip out gmail signature
    html = ActionController::Base.helpers.sanitize(html, tags: %w(strong em a div span ul ol li b i br p hr u em blockquote), attributes: %w(href target))
    html = html.gsub(/\n\n/, "<br><br>") # convert line breaks
    html = html.gsub(/\n\r?|\r\n?/, "<br>") # convert line breaks
    html = html.gsub(/\n/, "<br>") # convert line breaks
    html = html.split("<br>--<br>").first # strip out gmail signature
    html = html.presence || ""
    html = html.split("<div><br></div>\n<div>--</div>").first # strip out gmail signature
    html = html.presence || ""
    html = html.split("<br>--").first # strip out gmail signature
    html = html.presence || ""
    html = html.split("<br>\n--").first # strip out gmail signature
    html&.gsub!(/<style(?:\s+[^>]*)?>.*?<\/style>/mi, '') # remove styles
    html&.gsub!(/<xml(?:\s+[^>]*)?>.*?<\/xml>/mi, '') # remove xml
    html&.gsub!(/<!--.*?-->/m, '') # remove comments
    html&.gsub!('<![endif]-->', '') # remove comments
    html&.gsub!(/<(?:\/)?html(?:\s+[^>]*)?>/i, '') # remove html tags
    html&.gsub!(/<(?:\/)?head(?:\s+[^>]*)?>/i, '') # remove head tags
    html&.gsub!(/<(?:\/)?body(?:\s+[^>]*)?>/i, '') # remove body tags



    html&.gsub!(/\A<br\s*\/?>/, "") # remove <br> from very beginning of html
    html&.gsub!(/<div style="display:none;border:0px;width:0px;height:0px;overflow:hidden;">.+<\/div>/, "") # remove hidden divs / tracking pixels
    html&.gsub!(/src=\"cid\:\S+\"/, "src=\"\" style=\"display: none;\"") # remove attached images showing as broken inline images
    html&.gsub!("p.MsoNormal,p.MsoNoSpacing{margin:0}", "") # remove outlook styles

    empty_line_regex = /(<div>\n<div>\z)|(<br\s*\/?>\z)|(\n\z)/
    while html&.match?(empty_line_regex)
      html&.gsub!(empty_line_regex, "")
    end

    html&.gsub!(/<br\s*\/?>$/, "")&.gsub!(/<br\s*\/?>$/, "")&.gsub!(/^$\n/, "") # remove last unnecessary line break
    html&.gsub!(/\A(\s*<br\s*\/?>|\s*<p>\s*<\/p>|\s*<div>\s*<\/div>|\s*\n|\s*\r\n)*/, '')

    to_utf8(html)
  end

  def collage_from_attachments(attachments, existing_image_url: nil)
    return nil unless attachments.present?

    s3 = Fog::Storage.new({
      provider:              "AWS",
      aws_access_key_id:     ENV["AWS_ACCESS_KEY_ID"],
      aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
    })

    directory = s3.directories.new(key: ENV["AWS_BUCKET"])

    add_dev = "/development" unless Rails.env.production?
    folder = "uploads#{add_dev}/tmp/#{Date.today.strftime("%Y-%m-%d")}/"

    attachments.map do |att|
      file_key = "#{folder}#{SecureRandom.uuid}#{File.extname(att)}"
      file = directory.files.create(key: file_key, body: att, public: true, content_disposition: "inline", cache_control: "public, max-age=#{365.days.to_i}")
      file.public_url
    end
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
# rubocop:enable Metrics/AbcSize
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/ClassLength
# rubocop:enable Metrics/PerceivedComplexity
# rubocop:enable Metrics/CyclomaticComplexity
