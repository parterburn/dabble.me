require 'fileutils'

# Handle Emailed Entries
class EmailProcessor
  def initialize(email)
    @token = pick_meaningful_recipient(email.to, email.cc)
    @from = email.from[:email].downcase
    @subject = email.subject
    @stripped_html = email.vendor_specific.try(:[], :stripped_html)

    email.body&.gsub!(/src=\"data\:image\/(heic|jpeg|png)\;base64\,.*\"/, "src=\"\"") if email.body.present?
    email.body&.gsub!(/url\(data\:image\/(heic|jpeg|png)\;base64\,.*\)/, "url()") if email.body.present?
    email.raw_body&.gsub!(/src=\"data\:image\/(heic|jpeg|png)\;base64\,.*\"/, "src=\"\"") if email.raw_body.present?
    email.raw_body&.gsub!(/url\(data\:image\/(heic|jpeg|png)\;base64\,.*\)/, "url()") if email.raw_body.present?

    if email.raw_body.present? && email.raw_body.ascii_only? && email.body.ascii_only?
      @body = EmailReplyTrimmer.trim(email.body)
    else
      @body = email.body
    end
    @raw_body = email.raw_body
    @attachments = email.attachments
    @user = find_user_from_user_key(@token, @from)
  end

  def process
    unless @user.present?
      Sqreen.track('inbound_email_without_user')
      return false
    end

    best_attachment = nil
    if @user.is_pro? && @attachments.present?
      @attachments.each do |attachment|
        # Make sure attachments are at least 8kb so we're not saving a bunch of signuture/footer images
        file_size = File.size?(attachment.tempfile).to_i
        if (attachment.content_type == "application/octet-stream" || attachment.content_type =~ /^image\/(png|jpe?g|gif|heic)$/i || attachment.original_filename =~ /^.+\.(heic|HEIC|Heic)$/i) && (file_size <= 0 || file_size > 8000) && file_size > 20000 && !attachment.original_filename.in?(["tmiFinal.png"])
          best_attachment = attachment
          break
        end
      end
    end

    # If image came in as a URL, try saving that
    best_attachment_url = nil
    if best_attachment.blank? && @stripped_html.present?
      email_reply_html = @stripped_html&.split(/reply to this email with your /)&.first
      image_urls = email_reply_html&.scan(/<img\s.*?src=(?:'|")([^'">]+)(?:'|")/i)
      image_urls.flatten! if image_urls.present?
      if @user.is_pro? && image_urls.present? && image_urls.any?
        image_urls.each do |image_url|
          image_width, image_height = FastImage.size(image_url)
          image_type = FastImage.type(image_url)

          if image_type.in?([:gif, :jpeg, :png]) && image_height > 100  && image_width > 100
            best_attachment_url = image_url
            break
          end
        end
      end
    end

    @body&.gsub!(/\n\n\n/, "\n\n \n\n") # allow double line breaks
    @body = unfold_paragraphs(@body) unless @from.include?('yahoo.com') # fix wrapped plain text, but yahoo messes this up
    @body&.gsub!(/(?:\n\r?|\r\n?)/, '<br>') # convert line breaks
    @body = "<p>#{@body}</p>" # basic formatting
    @body&.gsub!(/[^>]\*(.+?)\*/i, '<b>\1</b>') # bold when bold needed
    @body&.gsub!(/<(http[s]?:\/\/\S+)>/, "(\\1)") # convert links to show up
    @body&.gsub!(/\[image\:\ Inline\ image\ [0-9]{1,2}\]/, '') # remove "inline image" text
    @body&.gsub!(/\[image\:\ (.+)\.[a-zA-Z]{3,4}\](<br>)?/, '') # remove "inline image" text

    date = parse_subject_for_date(@subject)
    existing_entry = @user.existing_entry(date.to_s)

    inspiration_id = parse_body_for_inspiration_id(@raw_body)

    if existing_entry.present?
      existing_entry.body += "<hr>#{@body}"
      existing_entry.body = existing_entry.sanitized_body if @user.is_free?
      existing_entry.original_email_body = @raw_body
      existing_entry.inspiration_id = inspiration_id if inspiration_id.present?
      if existing_entry.image_url_cdn.blank? && best_attachment.present?
        existing_entry.image = best_attachment
      elsif existing_entry.image_url_cdn.blank? && best_attachment_url.present?
        existing_entry.remote_image_url = best_attachment_url
      end
      begin
        existing_entry.save
      rescue
        existing_entry.body = existing_entry.body.force_encoding('iso-8859-1').encode('utf-8')
        existing_entry.original_email_body = existing_entry.original_email_body.force_encoding('iso-8859-1').encode('utf-8')
      end
      if existing_entry.save
        track_ga_event('Merged')
      else
        # error saving entry
        UserMailer.failed_entry(@user, existing_entry.errors.full_messages, date, @body).deliver_later
        Rails.logger.warn("Error saving existing entry #{existing_entry.id} from email: #{enexisting_entrytry.errors.full_messages}")
      end
    else
      params = { date: date, inspiration_id: inspiration_id }
      best_attachment.present? ? params.merge!(image: best_attachment) : params.merge!(remote_image_url: best_attachment_url)
      begin
        entry = @user.entries.create!(params.merge(body: @body, original_email_body: @raw_body))
      rescue
        @body = @body.force_encoding('iso-8859-1').encode('utf-8')
        @raw_body = @raw_body.force_encoding('iso-8859-1').encode('utf-8')
        entry = @user.entries.create!(params.merge(body: @body, original_email_body: @raw_body))
      end
      entry.body = entry.sanitized_body if @user.is_free?
      if entry.save
        track_ga_event('New')
        Sqreen.track('inbound_email')
      else
        UserMailer.failed_entry(@user, entry.errors.full_messages, date, @body).deliver_later
        Rails.logger.warn("Error saving entry from email: #{entry.errors.full_messages}")
      end
    end

    @user.increment!(:emails_received)
    begin
      UserMailer.second_welcome_email(@user).deliver_later if @user.emails_received == 1 && @user.entries.count == 1
    rescue StandardError => e
      Rails.logger.warn("Error sending second welcome email to #{@user.email}: #{e}")
    end
  end

  private

  def track_ga_event(action)
    if ENV['GOOGLE_ANALYTICS_ID'].present?
      tracker = Staccato.tracker(ENV['GOOGLE_ANALYTICS_ID'])
      tracker.event(category: 'Email Entry', action: action, label: @user.user_key)
    end
  end

  def pick_meaningful_recipient(to_recipients, cc_recipients)
    host_to = to_recipients.select {|k| k[:host] =~ /^(email|post)?\.?#{ENV['MAIN_DOMAIN'].gsub(".","\.")}$/i }.first
    if host_to.present?
      host_to[:token]
    elsif cc_recipients.present?
      # try CC's
      host_cc = cc_recipients.select {|k| k[:host] =~ /^(email|post)?\.?#{ENV['MAIN_DOMAIN'].gsub(".","\.")}$/i }.first
      host_cc[:token] if host_cc.present?
    end
  end

  def find_user_from_user_key(to_token, from_email)
    begin
      user = User.find_by user_key: to_token
    rescue JSON::ParserError => e
    end
    user.blank? ? User.find_by(email: from_email) : user
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
      Inspiration.without_imports_or_email_or_tips.each do |inspiration|
        if raw_body.include? inspiration.body.first(71)
          inspiration_id = inspiration.id
          break
        end
      end
    rescue
    end
    inspiration_id
  end
end
