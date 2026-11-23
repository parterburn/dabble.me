# rubocop:disable Metrics/AbcSize
# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/ClassLength
# rubocop:disable Metrics/PerceivedComplexity
# rubocop:disable Metrics/CyclomaticComplexity
require 'fileutils'

# Handle Emailed Entries
class EmailProcessor
  ENTRY_NOT_SAVED_COOLDOWN = 24.hours

  def initialize(email)
    @token = pick_meaningful_recipient(email.to, email.cc)
    @from = email.from[:email].downcase
    @to = email.to
    @cc = email.cc
    @bcc = email.bcc
    @subject = to_utf8(email.subject)
    @stripped_html = email.vendor_specific.try(:[], :stripped_html)
    @griddler_body = to_utf8(email.body&.dup)
    @raw_html = email.raw_html
    @body = clean_message(@griddler_body&.dup).presence || "No entry provided."

    @html = clean_html_version(@stripped_html)
    @authored_indentation_html = clean_authored_indentation_html(@raw_html, @griddler_body)
    @headers = email.headers
    @message_id = @headers&.dig("Message-ID")&.gsub("<", "")&.gsub(">", "")

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
    if sent_to_retired_ai_address?
      Sentry.capture_message("Dropped inbound email sent to the retired AI address", level: :info)
      return
    end

    if @user.present?
      Sentry.set_user(id: @user.id, email: @user.email)
      Sentry.set_tags(plan: @user.plan)

      best_attachment = nil
      best_attachment_url = nil
      if @user.is_pro? && @attachments.present?
        valid_attachments = []
        @attachments.each do |attachment|
          next unless attachment.present?

          # Make sure attachments are at least 20kb so we're not saving a bunch of signature/footer images
          file_size = File.size?(attachment.tempfile).to_i

          # skip signature images
          next if attachment&.original_filename.to_s.downcase.include?("linkedin_icon_circle.svg.png")
          next if ignored_attachment_domain?(attachment&.original_filename)

          if (attachment.content_type == "application/octet-stream" || attachment.content_type =~ /^image\/(png|jpe?g|webp|gif|heic|heif)$/i || attachment&.original_filename.to_s =~ /^(.+\.(heic|heif))$/i) && file_size > 20_000
            next if ignored_by_user?(attachment)

            valid_attachments << attachment
          end
        end

        if valid_attachments.size > 1
          best_attachment_url = "mailgun_collage:#{@message_id}"
        elsif valid_attachments.any?
          best_attachment = valid_attachments.first
        end
      end

      # If image came in as a URL, download it with SafeRemoteFetch and store
      # the bytes. Email URLs are never passed to CarrierWave remote_image_url=
      # or open-uri. We do not support a mix of attachments and inline images.
      @inline_image_files = []
      if best_attachment_url.blank? && best_attachment.blank? && @stripped_html.present?
        email_reply_html = @stripped_html&.split(/reply to this email with your /i)&.first
        image_urls = email_reply_html&.scan(/<img\s.*?src=(?:'|")([^'">]+)(?:'|")/i)
        image_urls.flatten! if image_urls.present?
        if @user.is_pro? && image_urls.present? && image_urls.any?
          image_urls.each do |image_url|
            file = download_inline_image(image_url)
            @inline_image_files << file if file
            break if @inline_image_files.size >= CollageGenerator::MAX_IMAGES
          end
        end
      end

      date = parse_subject_for_date(@subject)
      existing_entry = @user.existing_entry(date.to_s)
      inspiration_id = parse_body_for_inspiration_id(@raw_body)
      if @user.is_pro?
        @body = preferred_pro_body
      elsif @user.is_free? && @authored_indentation_html.present?
        @body = clean_message(without_leading_quote_markers(@griddler_body)).presence || @body
      end

      if existing_entry.present?
        existing_entry.original_email = @inbound_email_params

        if existing_entry.body.present?
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
            existing_entry.update(uploading_image: true)
            process_single_image(existing_entry, best_attachment)
          elsif best_attachment_url.present? && best_attachment_url.starts_with?("mailgun_collage:")
            ImageCollageJob.perform_later_for_mailgun(existing_entry.id, message_id: best_attachment_url.gsub("mailgun_collage:", ""), recipient_key: collage_recipient_key)
          elsif @inline_image_files.present?
            attach_inline_images(existing_entry, @inline_image_files)
          end
        elsif existing_entry.image_url_cdn.present?
          if best_attachment.present?
            image_urls = collage_from_attachments([best_attachment])
            ImageCollageJob.perform_later(existing_entry.id, urls: image_urls)
          elsif best_attachment_url.present? && best_attachment_url.starts_with?("mailgun_collage:")
            # Multi-attachment email landing on an entry that already has an image.
            # Hand off to ImageCollageJob — it'll fetch the attachments from Mailgun
            # via the message_id and merge them with the existing entry image itself
            # (see ImageCollageJob#collage_from_mailgun_attachments). Previously this
            # fell into the `elsif` below and passed the literal "mailgun_collage:…"
            # marker into CollageGenerator as a URL, which blew up with
            # URI::InvalidURIError.
            ImageCollageJob.perform_later_for_mailgun(existing_entry.id, message_id: best_attachment_url.gsub("mailgun_collage:", ""), recipient_key: collage_recipient_key)
          elsif @inline_image_files.present?
            existing_image = existing_entry.image_url_cdn(cloudflare: false) if existing_entry.image.present?
            existing_entry.update(uploading_image: true)
            attach_inline_images(existing_entry, @inline_image_files, existing_url: existing_image)
          end
        end

        unless existing_entry.save
          Sentry.capture_message("Error processing entry via email", level: :error, extra: { reason: "Could not save existing entry", subject: @subject, entry_id: existing_entry&.id, errors: existing_entry&.errors&.full_messages })
          UserMailer.failed_entry(@user, existing_entry.errors.full_messages.to_sentence, date, @body).deliver_now # not queued: job arguments would hold the entry text in Redis
          raise "Failed entry" # for mailgun to retry
        end
      else
        begin
          params = { date: date, inspiration_id: inspiration_id, body: @body, original_email_body: @raw_body }
          entry = @user.entries.create!(params)
          entry.save
          if best_attachment.present?
            process_single_image(entry, best_attachment)
          elsif best_attachment_url.present? && best_attachment_url.starts_with?("mailgun_collage:")
            ImageCollageJob.perform_later_for_mailgun(entry.id, message_id: best_attachment_url.gsub("mailgun_collage:", ""), recipient_key: collage_recipient_key)
          elsif @inline_image_files.present?
            attach_inline_images(entry, @inline_image_files)
          end
        rescue ActiveRecord::RecordInvalid => error
          @error = error
          if error.to_s.include?("Image Failed to manipulate")
            entry = @user.entries.create!(params.except(:image, :remote_image_url).merge(body: @body, original_email_body: @raw_body))
            Sentry.capture_message("Error processing image via email", level: :error, extra: { reason: "Image Failed to manipulate", error: error, image: best_attachment, remote_image_url: best_attachment_url, subject: @subject, entry_id: entry&.id })
          else
            Sentry.capture_message("Error processing entry via email", level: :error, extra: { reason: "ActiveRecord::RecordInvalid", error: error, subject: @subject })
          end
        rescue => error
          @error = error
          Sentry.capture_message("Error processing entry via email", level: :error, extra: { error: error, subject: @subject })
          @body = @body.force_encoding('iso-8859-1').encode('utf-8')
          @raw_body = @raw_body.force_encoding('iso-8859-1').encode('utf-8')
          entry = @user.entries.create!(params.merge(body: @body, original_email_body: @raw_body))
        end
        entry&.original_email = @inbound_email_params
        entry&.body = entry&.sanitized_body if @user.is_free?
        if entry&.save
          # all good
        else
          if entry.present?
            record_errors = entry.errors.full_messages.to_sentence
          else
            record_errors = @error.full_messages.to_sentence
          end
          Sentry.capture_message("Error processing entry via email", level: :error, extra: { reason: "Could not save new entry (failed_entry email sent to hello@dabble.me)", errors: entry&.errors&.full_messages, rescue_error: @error, date: date })
          UserMailer.failed_entry(@user, record_errors, date, @body).deliver_now # not queued: job arguments would hold the entry text in Redis
          raise "Failed entry" # for mailgun to retry
        end
      end

      @user.increment!(:emails_received)
      begin
        UserMailer.second_welcome_email(@user).deliver_later if @user.emails_received == 1 && @user.entries.count == 1
      rescue StandardError => _e
        Sentry.capture_message("Error sending email", level: :error, extra: { email_type: "Second Welcome Email" })
      end
    else # no user found
      # Mail to a reset (retired) posting address lands here, spam included,
      # so only alert when the sender is one of our users: that's someone
      # whose entry was dropped, e.g. a reply to an old address that failed
      # SPF/DKIM. Everyone else stays silent.
      sender = User.find_by(email: @from) if @from.present?
      if sender
        Sentry.set_user(id: @token, email: @from)
        Sentry.capture_message("Inbound entry not associated to user", level: :warning, extra: { subject: @subject, from: @from })
        if send_entry_not_saved?(sender)
          begin
            # Journal text stays out of the job arguments.
            UserMailer.entry_not_saved(sender).deliver_later
          rescue StandardError => _e
            Sentry.capture_message("Error sending email", level: :error, extra: { email_type: "Entry not saved" })
          end
        end
      else
        Rails.logger.info("Inbound email matched no user (token: #{@token.inspect})")
      end
    end
  end

  private

  attr_reader :to, :cc, :bcc

  # This branch runs when From failed SPF/DKIM, so anyone can forge an
  # account's address and make us mail it. One notice per account per day,
  # and none to an address that bounces or an account being deleted.
  # unless_exist makes the write the lock: only the first writer gets true.
  # If the cache is down the write returns false and the notice is skipped.
  def send_entry_not_saved?(user)
    return false if user.deletion_pending? || user.emails_bounced.to_i.positive?

    Rails.cache.write("entry_not_saved_sent:#{user.id}", true, expires_in: ENTRY_NOT_SAVED_COOLDOWN, unless_exist: true)
  end

  # Only when the email matched the user's posting address. A user found by
  # their verified From address may have sent to any token, and the collage
  # job's recipient check is a substring match.
  def collage_recipient_key
    @token if @token.present? && @token == @user&.user_key
  end

  def all_recipients
    (to.to_a + cc.to_a + bcc.to_a)
  end

  # Mail to <user_key>@ai.<domain> used to get a reply from the AI assistant.
  # That address is retired: drop the email rather than fall back to finding
  # the user by sender and saving it as a normal entry.
  def sent_to_retired_ai_address?
    return false if @token.present?

    ai_host = "ai.#{ENV['MAIN_DOMAIN']}"
    all_recipients.any? { |recipient| recipient[:host].to_s.casecmp?(ai_host) }
  end

  def pick_meaningful_recipient(to_recipients, cc_recipients)
    escaped_domain = Regexp.escape(ENV['MAIN_DOMAIN'].to_s)
    host_to = to_recipients.select {|k| k[:host] =~ /^(email|post)?\.?#{escaped_domain}$/i }.first
    if host_to.present?
      host_to[:token]
    elsif cc_recipients.present?
      # try CC's
      host_cc = cc_recipients.select {|k| k[:host] =~ /^(email|post)?\.?#{escaped_domain}$/i }.first
      host_cc[:token] if host_cc.present?
    end
  end

  def find_user_from_user_key(to_token, from_email)
    user = User.find_by(user_key: to_token) if to_token.present?
    return user if user.present?
    return nil unless from_email.present? && authenticated_from_sender?

    User.find_by(email: from_email)
  rescue JSON::ParserError => _e
    nil
  end

  def authenticated_from_sender?
    return false unless @headers.is_a?(Hash)

    sflag = header_value('X-Mailgun-Sflag')
    return false if sflag&.casecmp?('yes')

    spf = header_value('X-Mailgun-Spf')
    dkim = header_value('X-Mailgun-Dkim-Check-Result')
    return false if spf&.casecmp?('fail') || spf&.casecmp?('softfail') || dkim&.casecmp?('fail')

    spf&.casecmp?('pass') || dkim&.casecmp?('pass')
  end

  def header_value(name)
    return nil unless @headers.is_a?(Hash)

    pair = @headers.find { |k, _v| k.to_s.casecmp?(name) }
    pair&.last.to_s.strip.presence
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
    text = +''
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
    return unless body.present?

    # Drop raw <img> tags. The plain-text part is not run through the HTML
    # safe list, so a literal remote <img> here would be stored and act as a
    # tracking pixel. Inline images are handled from the HTML part instead.
    body&.gsub!(/<img\b[^>]*>/i, "")

    # Remove embedded images and data
    body&.gsub!(/src=\"data\:image\/(jpeg|png)\;base64\,.*?\"/, "src=\"\"")
    body&.gsub!(/url\(data\:image\/(jpeg|png)\;base64\,.*?\)/, "url()")

    # Handle line breaks and paragraphs
    body&.gsub!(/\n\n\n/, "\n\n \n\n") # allow double line breaks
    body = unfold_paragraphs(body) unless @from.include?('yahoo.com') # fix wrapped plain text

    # Replace inline image indicators
    body&.gsub!(/\[image\:\ Inline\ image\ [0-9]{1,2}\]/, "(see attached image)")

    # Convert line breaks for various mail clients
    body&.gsub!(/(?:\n\n?|\n\n?)/, "<br><br>") # iOS Mail double breaks
    body&.gsub!(/(?:\n\r?|\r\n?)/, "<br>") # standard line breaks

    # Handle literal \n strings (from some email clients)
    body&.gsub!(/\\n\\n/, "<br><br>")
    body&.gsub!(/\\n/, "<br>")

    # Handle links and signatures
    body&.gsub!(/<(http[s]?:\/\/\S*?)>/, "(\\1)") # make links visible
    body&.gsub!(/--( \*)?$\z/, "") # remove gmail signature break
    body&.gsub!(%r{<br><br>\s*—\s*<br><br>\s*[^<]+?\s*\z}m, "")
    body&.gsub!(%r{<br>\s*#{mobile_signature_pattern}\s*\z}i, "")
    body&.gsub!(%r{<br><br>\s*#{mobile_signature_pattern}\s*\z}i, "")

    # Remove unnecessary HTML elements
    body&.gsub!(/<style(?:\s+[^>]*)?>.*?<\/style>/mi, '') # styles
    body&.gsub!(/<xml(?:\s+[^>]*)?>.*?<\/xml>/mi, '') # xml
    body&.gsub!(/<!--.*?-->/m, '') # comments
    body&.gsub!('<![endif]-->', '') # conditional comments

    # Aggressively clean up trailing breaks
    body&.gsub!(/<br\s*\/?>\s*(<br\s*\/?>)*\s*$/, "")
    body&.gsub!(/\s*$/, "")

    # Clean up leading line breaks and empty elements
    body&.gsub!(/\A(\s*<br\s*\/?>|\s*<p>\s*<\/p>|\s*<div>\s*<\/div>|\s*\n|\s*\r\n)*/, '')

    # Remove Outlook styles
    body&.gsub!("p.MsoNormal,p.MsoNoSpacing{margin:0}", "")

    # Final cleanup and formatting
    body = body&.strip
    return unless body.present?

    # Convert to UTF-8
    body = to_utf8(body)

    # Use div instead of p for consistency
    if body =~ /\A<(div|p|span)[^>]*>/ && body =~ /<\/(div|p|span)>\z/
      # Already has a container element
      body
    else
      "<div>#{body}</div>"
    end
  end

  def to_utf8(content)
    return unless content.present?
    content = content.gsub("\0", "") # remove null characters
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

    html = remove_html_document_wrappers(html)
    html = remove_unsafe_html_content(html)
    html = remove_gmail_signature(html)
    html = Rinku.auto_link(html, :all, 'target="_blank"')

    safe_list_sanitizer = Rails::HTML5::SafeListSanitizer.new
    html = safe_list_sanitizer.sanitize(html, tags: %w(strong em a div span ul ol li b i br p hr u em blockquote), attributes: %w(href target))
    html = remove_html_signatures(html)
    fragment = Nokogiri::HTML5.fragment(html)
    normalize_empty_html_blocks(fragment)
    normalize_html_text_nodes(fragment)
    hoist_leading_breaks_after_inline(fragment)
    normalize_html_block_edge_breaks(fragment)
    trim_html_edge_breaks(fragment)
    remove_list_separator_breaks(fragment)
    fragment.css('a[href]').each { |link| link['target'] = '_blank' }

    html = to_utf8(fragment.to_html.strip)
    return unless html.present?

    html
  end

  def normalized_visible_text(html)
    fragment = Nokogiri::HTML5.fragment(html.to_s)
    fragment.css('br').each { |node| node.replace(Nokogiri::XML::Text.new(' ', node.document)) }
    fragment.css(HTML_BLOCK_ELEMENTS.join(',')).each do |node|
      node.add_next_sibling(Nokogiri::XML::Text.new(' ', node.document))
    end
    fragment.text.unicode_normalize(:nfkc).gsub(/\s+/, ' ').strip
  end

  def clean_authored_indentation_html(raw_html, griddler_body)
    return unless raw_html.present? && griddler_body.present?

    has_quote_markers = griddler_body.lines.any? { |line| line.match?(/\A[[:blank:]]*>/) }
    fragment = Nokogiri::HTML5.fragment(raw_html)
    fragment.css('.gmail_quote, .gmail_signature').remove
    blockquote_count = fragment.css('blockquote').count
    unsafe_content = unsafe_raw_html?(fragment)
    cleaned_html = clean_html_version(fragment.to_html) if has_quote_markers && blockquote_count.positive? && !unsafe_content
    text_matches = cleaned_html.present? &&
                   normalized_visible_text(cleaned_html) == normalized_unquoted_plain_text(griddler_body)
    accepted = has_quote_markers && blockquote_count.positive? && !unsafe_content && text_matches

    cleaned_html if accepted
  end

  def normalized_unquoted_plain_text(body)
    without_leading_quote_markers(body)
        .unicode_normalize(:nfkc)
        .gsub(/\s+/, ' ')
        .strip
  end

  def without_leading_quote_markers(body)
    body.to_s.lines.map { |line| line.sub(/\A[[:blank:]]*(?:>[[:blank:]]*)+/, '') }.join
  end

  def unsafe_raw_html?(fragment)
    unsafe_elements = %w[script iframe object embed form input button textarea select option link meta base svg math]
    return true if fragment.css(unsafe_elements.join(',')).any?

    fragment.css('*').any? do |node|
      node.attribute_nodes.any? do |attribute|
        attribute.name.match?(/\Aon/i) ||
          (%w[href src xlink:href formaction].include?(attribute.name.downcase) &&
            attribute.value.match?(/\A\s*(?:javascript|vbscript|data):/i))
      end
    end
  end

  def preferred_pro_body
    return @authored_indentation_html if @authored_indentation_html.present?
    return @body unless @html.present?

    plain_text = normalized_visible_text(@body)
    stripped_html_text = normalized_visible_text(@html)
    stripped_html_is_strict_prefix = plain_text.start_with?(stripped_html_text) &&
                                     plain_text != stripped_html_text

    return @html unless stripped_html_is_strict_prefix

    @body
  end

  def collage_from_attachments(attachments, existing_image_url: nil)
    return nil unless attachments.present?
    add_dev = "/development" unless Rails.env.production?
    folder = "uploads#{add_dev}/tmp/#{Date.today.strftime("%Y-%m-%d")}/"

    attachments.map do |att|
      file_key = "#{folder}#{SecureRandom.uuid}#{File.extname(att)}"
      file = UploadToS3.new(file_key: file_key, body: att).call
      file.public_url
    end
  end

  def collage_from_urls(urls)
    return nil unless urls.present?

    urls.reject! { |url| url&.include?("googleusercontent.com/mail-sig/") || ignored_attachment_domain?(url) }
    urls.compact!

    if urls.size == 1 && urls.first.starts_with?("http")
      urls.first
    elsif urls.any?
      CollageGenerator.new(urls: urls, user: @user).tmp_s3_url
    end
  end

  def process_single_image(entry, attachment)
    file_key = "uploads/tmp/#{entry.user.id}/#{Date.today.strftime("%Y-%m-%d")}/#{SecureRandom.uuid}#{File.extname(attachment.original_filename)}"
    file = UploadToS3.new(file_key: file_key, body: attachment.read).call

    ProcessEntryImageJob.perform_later(
      entry.id,
      file.key
    )
  end

  def mobile_signature_pattern
    /sent from my (?:iphone|ipad|android|mobile device|phone|galaxy|pixel)/i
  end

  IGNORED_ATTACHMENT_DOMAINS = %w[wisestamp.com ytimg.com].freeze

  # Images an admin told us to skip for this user, such as their signature
  # logo (IgnoredEmailImage). Loaded once per email.
  def ignored_images
    @ignored_images ||= IgnoredEmailImage.matcher_for(@user)
  end

  def ignored_by_user?(attachment)
    ignored_images.ignore?(name: attachment.original_filename) do
      ImageFingerprint.from_file(attachment.tempfile.path)
    end
  end

  def ignored_attachment_domain?(value)
    return false if value.blank?

    text = value.to_s.downcase
    IGNORED_ATTACHMENT_DOMAINS.any? { |domain| text.include?(domain) }
  end

  def safe_inline_image_url?(raw_url)
    uri = URI.parse(raw_url.to_s.strip)
    return false unless uri.is_a?(URI::HTTPS) || (!Rails.env.production? && uri.is_a?(URI::HTTP))
    return false if uri.userinfo.present?

    SafeRemoteFetch.public_host?(uri)
  rescue URI::InvalidURIError
    false
  end

  INLINE_IMAGE_EXTENSIONS = { jpeg: ".jpg", png: ".png", gif: ".gif" }.freeze

  def download_inline_image(image_url)
    return if ignored_attachment_domain?(image_url)
    return if skipped_signature_url?(image_url)
    return if ignored_images.ignore?(name: image_url) { nil }
    return unless safe_inline_image_url?(image_url)

    fetched = SafeRemoteFetch.fetch(image_url, https_only: Rails.env.production?)
    return unless fetched.ok?

    io = StringIO.new(fetched.body)
    image_type = FastImage.type(io)
    return unless image_type.in?([:gif, :jpeg, :png])

    io.rewind
    image_width, image_height = FastImage.size(io)
    return if image_height && image_width && image_height < 100 && image_width < 100
    return if ignored_images.ignore?(name: image_url) { ImageFingerprint.from_bytes(fetched.body) }

    file = Tempfile.new(["inline", INLINE_IMAGE_EXTENSIONS[image_type]])
    file.binmode
    file.write(fetched.body)
    file.rewind
    file
  end

  def skipped_signature_url?(image_url)
    text = image_url.to_s.downcase
    text.include?("googleusercontent.com/mail-sig/") ||
      text.include?("linkedin_icon_circle.svg.png") ||
      text.include?("app.v1ce.co.uk")
  end

  # files are local downloads. existing_url, when present, is this entry's
  # own stored image, not a URL from the email.
  def attach_inline_images(entry, files, existing_url: nil)
    image_file = nil
    extras = []
    image_file, content_type, extras = compose_inline_image(files, existing_url)
    return if image_file.blank?

    entry.uploading_image = false
    entry.image = uploaded_image_file(image_file, content_type)
    entry.save
  ensure
    Array(extras).each { |file| close_tempfile(file) }
    Array(files).each { |file| close_tempfile(file) }
  end

  def close_tempfile(file)
    return if file.nil? || (file.respond_to?(:closed?) && file.closed?)

    file.close
  rescue StandardError
    nil
  end

  # New inline images are composed first, up to the collage limit. An existing
  # photo is merged in a second pass so it is not the ninth item that
  # CollageGenerator drops with .first(MAX_IMAGES).
  def compose_inline_image(files, existing_url)
    files = Array(files)
    intermediates = []
    if files.size == 1 && existing_url.blank?
      type = Marcel::MimeType.for(files.first)
      files.first.rewind if files.first.respond_to?(:rewind)
      type = "image/jpeg" unless Entry::ALLOWED_IMAGE_TYPES.include?(type.to_s)
      return [files.first, type, intermediates]
    end

    inline_source = if files.size == 1
      files.first.path
    else
      staged = CollageGenerator.new(urls: files.map(&:path), user: @user, allow_local_paths: true).tempfile
      intermediates << staged if staged
      staged&.path
    end
    return [nil, nil, intermediates] if inline_source.blank?
    return [intermediates.first, "image/jpeg", intermediates] if existing_url.blank?

    merged = CollageGenerator.new(
      urls: [inline_source, existing_url],
      user: @user,
      allow_local_paths: true
    ).tempfile
    intermediates << merged if merged
    [merged, "image/jpeg", intermediates]
  end

  def uploaded_image_file(file, content_type)
    ActionDispatch::Http::UploadedFile.new(
      tempfile: file,
      filename: File.basename(file.path),
      type: content_type
    )
  end

  HTML_BLOCK_ELEMENTS = %w[blockquote br div hr li ol p ul].freeze
  HTML_EMPTY_LINE_ELEMENTS = %w[div p].freeze

  def remove_html_document_wrappers(html)
    html = html.dup
    html.gsub!(/\A\s*<!doctype[^>]*>\s*/i, '')
    html.gsub!(/\A\s*<html\b[^>]*>\s*/i, '')
    html.gsub!(%r{\s*</html>\s*\z}i, '')
    html.gsub!(/\A\s*<head\b[^>]*>.*?<\/head>\s*/mi, '')
    html.gsub!(/\A\s*<body\b[^>]*>\s*/i, '')
    html.gsub!(%r{\s*</body>\s*\z}i, '')
    html.gsub!(/<br\s*\/?>/i, '<br>')
    html
  end

  # Remove content that depends on attributes before sanitization strips those
  # attributes and makes the content indistinguishable from normal email text.
  def remove_unsafe_html_content(html)
    html = html.dup
    html.gsub!(/<style(?:\s+[^>]*)?>.*?<\/style>/mi, '')
    html.gsub!(/<xml(?:\s+[^>]*)?>.*?<\/xml>/mi, '')
    html.gsub!(/<!--.*?-->/m, '')
    html.gsub!('<![endif]-->', '')
    html.gsub!(/<div\b[^>]*style=(["'])[^"']*display\s*:\s*none[^"']*\1[^>]*>.*?<\/div>/im, '')
    html
  end

  def remove_gmail_signature(html)
    html.split(%r{<br\b[^>]*\bid=(["'])lineBreakAtBeginningOfSignature\1[^>]*>}i, 2).first || html
  end

  # Signature matching happens after sanitization so client-specific classes
  # and styles cannot prevent otherwise equivalent markup from matching.
  def remove_html_signatures(html)
    html = html.split(%r{<br>\s*--(?:\s*<br>|\s*$)}i, 2).first || html
    html = html.split(%r{<div>\s*<br>\s*</div>\s*<div>\s*--\s*</div>}i, 2).first || html
    html = html.split(%r{<div>\s*<br>\s*--\s*<br>\s*</div>}i, 2).first || html
    html = html.split(%r{<span>\s*--\s*</span>\s*<br>}i, 2).first || html
    html = html.gsub(%r{<br>\s*—\s*<br>\s*[^<]+(?=(?:</(?:div|p|span)>)?\s*\z)}m, '')
    html = html.gsub(%r{<(?:div|p|span)>\s*—\s*</(?:div|p|span)>\s*<(?:div|p|span)>\s*[^<]+\s*</(?:div|p|span)>\s*\z}m, '')
    html = html.gsub(%r{<br>\s*#{mobile_signature_pattern}(?=(?:</(?:div|p|span)>)?\s*\z)}im, '')
    html.gsub(%r{<(?:div|p|span)>\s*#{mobile_signature_pattern}\s*</(?:div|p|span)>\s*\z}im, '')
  end

  # Empty block elements are how clients such as Apple Mail represent a blank
  # line. Collapse an internal run to one <br>, and discard leading/trailing
  # runs so an email cannot acquire padding around its content.
  # Gmail leaves the first paragraph as text in the wrapper. A <br> between
  # that text and the next block collapses, so wrap the text first.
  def normalize_empty_html_blocks(fragment)
    blank_blocks = fragment.css(HTML_EMPTY_LINE_ELEMENTS.join(',')).select { |node| blank_html_block?(node) }
    preserve_as_break = blank_blocks.index_with do |node|
      previous_node = nearest_non_whitespace_sibling(node, :previous)
      first_in_run = !blank_html_block?(previous_node)
      first_in_run &&
        meaningful_sibling(node, :previous).present? &&
        meaningful_sibling(node, :next).present?
    end

    blank_blocks.sort_by { |node| -node.ancestors.length }.each do |node|
      next unless node.parent

      if preserve_as_break[node]
        separate_unwrapped_paragraph(node)
        node.replace(Nokogiri::XML::Node.new('br', node.document)) if node.parent
      else
        node.remove
      end
    end
  end

  def blank_html_block?(node)
    return false unless node&.element? && HTML_EMPTY_LINE_ELEMENTS.include?(node.name)

    node.children.all? do |child|
      whitespace_html_text_node?(child) ||
        (child.element? && (child.name == 'br' || blank_html_block?(child)))
    end
  end

  def meaningful_sibling(node, direction)
    sibling = nearest_non_whitespace_sibling(node, direction)
    while blank_html_block?(sibling)
      sibling = nearest_non_whitespace_sibling(sibling, direction)
    end
    sibling
  end

  def nearest_non_whitespace_sibling(node, direction)
    sibling = direction == :previous ? node.previous_sibling : node.next_sibling
    while whitespace_html_text_node?(sibling)
      sibling = direction == :previous ? sibling.previous_sibling : sibling.next_sibling
    end
    sibling
  end

  # Newlines inside a text node are authored line breaks. Whitespace-only text
  # nodes between tags are source formatting and should not become <br> tags.
  def normalize_html_text_nodes(fragment)
    fragment.xpath('.//text()').to_a.each do |node|
      next unless node.parent

      content = node.text.gsub(/\\r\\n|\\n|\\r/, "\n").gsub(/\r\n?/, "\n")
      content = normalize_text_boundary_newlines(node, content)
      if content.strip.empty?
        normalize_html_whitespace_node(node)
      elsif content.include?("\n")
        replace_text_newlines_with_breaks(node, content)
      else
        node.content = content
      end
    end
  end

  # Pretty-printed HTML commonly puts newlines around inline children. Those
  # boundary newlines are collapsible whitespace, unlike a newline surrounded
  # by text within the same node.
  def normalize_text_boundary_newlines(node, content)
    leading_space = node.previous_sibling.present? && !html_block_node?(node.previous_sibling) ? ' ' : ''
    trailing_space = node.next_sibling.present? && !html_block_node?(node.next_sibling) ? ' ' : ''
    content = content.sub(/\A[ \t]*(?:\n[ \t]*)+/, leading_space)
    content.sub(/(?:[ \t]*\n)+[ \t]*\z/, trailing_space)
  end

  def normalize_html_whitespace_node(node)
    if node.previous_sibling.nil? || node.next_sibling.nil? ||
       html_block_node?(node.previous_sibling) || html_block_node?(node.next_sibling)
      node.remove
    else
      node.content = ' '
    end
  end

  def replace_text_newlines_with_breaks(node, content)
    parts = content.split("\n", -1)
    parts.each_with_index do |part, index|
      node.add_previous_sibling(Nokogiri::XML::Text.new(part, node.document)) if part.present?
      node.add_previous_sibling(Nokogiri::XML::Node.new('br', node.document)) if index < parts.length - 1
    end
    node.remove
  end

  # Gmail can encode the same blank line either as an empty block between
  # paragraphs or as a <br> at the edge of a content block. Move edge breaks
  # between block siblings so both representations render identically.
  # List items are excluded: email clients often end an <li> with <br>, and
  # promoting that break between siblings inserts invalid <ul>/<ol> children
  # that render as blank lines between bullets.
  def normalize_html_block_edge_breaks(fragment)
    fragment.css('blockquote,div,p').each do |block|
      normalize_html_block_edge_break(block, :previous)
      normalize_html_block_edge_break(block, :next)
    end
  end

  def normalize_html_block_edge_break(block, direction)
    edge_child = direction == :previous ? first_content_child(block) : last_content_child(block)
    return unless edge_child&.name == 'br'

    sibling = nearest_non_whitespace_sibling(block, direction)
    return unless sibling&.element? && (sibling.name == 'br' || html_block_node?(sibling))

    loop do
      edge_child = direction == :previous ? first_content_child(block) : last_content_child(block)
      break unless edge_child&.name == 'br'

      edge_child.remove
    end
    return if sibling.name == 'br'

    separator = Nokogiri::XML::Node.new('br', block.document)
    direction == :previous ? block.add_previous_sibling(separator) : block.add_next_sibling(separator)
  end

  # A <br> at the start of the next block is a blank line. Trim would delete it
  # when the previous paragraph is unwrapped text, because that break is not
  # between blocks yet. Wrap the text and keep one <br>, matching later gaps.
  def hoist_leading_breaks_after_inline(fragment)
    fragment.css('blockquote,div,p').to_a.each do |block|
      next if block.parent.nil? || block.parent.name == 'p'
      next unless first_content_child(block)&.name == 'br'
      next if blank_html_block?(block)
      run = paragraph_run_before(block)
      next if run.none? { |member| meaningful_inline_text?(member) }

      remove_preceding_break_run(block)
      wrap_nodes(run)
      strip_leading_breaks(block)
      block.add_previous_sibling(Nokogiri::XML::Node.new('br', block.document))
    end
  end

  # The empty block is about to become a <br>. When it separates unwrapped
  # text from a later paragraph, that <br> would collapse; wrap the text so
  # the break sits between blocks like the later ones.
  def separate_unwrapped_paragraph(node)
    return if node.parent.nil? || node.parent.name == 'p'

    following = following_paragraph_block(node)
    return unless following
    run = paragraph_run_before(node)
    return if run.none? { |member| meaningful_inline_text?(member) }

    remove_preceding_break_run(node)
    wrap_nodes(run)
    remove_break_run_between(node, following)
  end

  def following_paragraph_block(node)
    sibling = meaningful_sibling(node, :next)
    sibling = meaningful_sibling(sibling, :next) while sibling&.element? && sibling.name == 'br'
    sibling if structural_html_block?(sibling)
  end

  def remove_preceding_break_run(node)
    sibling = node.previous_sibling
    while sibling && break_or_whitespace?(sibling)
      earlier = sibling.previous_sibling
      sibling.remove
      sibling = earlier
    end
  end

  def remove_break_run_between(node, following)
    sibling = node.next_sibling
    while sibling && sibling != following
      nxt = sibling.next_sibling
      sibling.remove if break_or_whitespace?(sibling)
      sibling = nxt
    end
  end

  def strip_leading_breaks(block)
    while (child = block.child) && break_or_whitespace?(child)
      child.remove
    end
  end

  # Inline content that ends at node, skipping a <br> run that sits against node.
  def paragraph_run_before(node)
    sibling = node.previous_sibling
    sibling = sibling.previous_sibling while sibling && break_or_whitespace?(sibling)
    nodes = []
    while inline_run_member?(sibling)
      nodes.unshift(sibling)
      sibling = sibling.previous_sibling
    end
    nodes.shift while nodes.first && whitespace_html_text_node?(nodes.first)
    nodes.pop while nodes.last && whitespace_html_text_node?(nodes.last)
    nodes
  end

  def wrap_nodes(nodes)
    wrapper = Nokogiri::XML::Node.new('div', nodes.first.document)
    nodes.first.add_previous_sibling(wrapper)
    nodes.each { |member| wrapper.add_child(member) }
    wrapper
  end

  def inline_run_member?(node)
    whitespace_html_text_node?(node) || inline_paragraph_node?(node)
  end

  def inline_paragraph_node?(node)
    return false unless node
    return false if whitespace_html_text_node?(node)
    return true if node.text?
    return false unless node.element?

    node.name != 'br' && !structural_html_block?(node)
  end

  def meaningful_inline_text?(node)
    node.text.to_s.delete("\u00A0").strip.present?
  end

  def break_or_whitespace?(node)
    node&.name == 'br' || whitespace_html_text_node?(node)
  end

  def structural_html_block?(node)
    node&.element? && %w[blockquote div hr li ol p ul].include?(node.name)
  end

  def trim_html_edge_breaks(fragment)
    ([fragment] + fragment.css('blockquote,div,li,p').to_a).each do |parent|
      first_content_child(parent)&.remove while first_content_child(parent)&.name == 'br'
      last_content_child(parent)&.remove while last_content_child(parent)&.name == 'br'
    end
  end

  # <br> is not a valid direct child of <ul>/<ol>; email clients and older
  # cleaners sometimes leave them between <li>s, which browsers render as gaps.
  def remove_list_separator_breaks(fragment)
    fragment.css('ul > br, ol > br').each(&:remove)
  end

  def first_content_child(parent)
    parent.children.find { |child| !whitespace_html_text_node?(child) }
  end

  def last_content_child(parent)
    parent.children.reverse.find { |child| !whitespace_html_text_node?(child) }
  end

  def whitespace_html_text_node?(node)
    node&.text? && node.text.delete("\u00A0").strip.empty?
  end

  def html_block_node?(node)
    node&.element? && HTML_BLOCK_ELEMENTS.include?(node.name)
  end
end
# rubocop:enable Metrics/AbcSize
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/ClassLength
# rubocop:enable Metrics/PerceivedComplexity
# rubocop:enable Metrics/CyclomaticComplexity
