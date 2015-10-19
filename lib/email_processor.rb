require 'fileutils'

# Handle Emailed Entries
class EmailProcessor
  def initialize(email)
    @token = pick_meaningful_recipient(email.to, email.cc)
    @from = email.from[:email].downcase
    @subject = email.subject
    if email.raw_body.present? && email.raw_body.ascii_only? && email.body.ascii_only?
      @body = EmailReplyParser.parse_reply(email.body)
    else
      @body = email.body
    end
    @raw_body = email.raw_body
    @attachments = email.attachments
    @user = find_user_from_user_key(@token, @from)
  end

  def process
    return false unless @user.present?
    filepicker_url = ''

    if @user.is_pro? && @attachments.present?
      @attachments.each do |attachment|
        if attachment.content_type =~ /^image\/(png|jpe?g|gif)$/i
          dir = FileUtils.mkdir_p("public/email_attachments/#{@user.user_key}")
          file = File.join(dir, attachment.original_filename)
          FileUtils.mv attachment.tempfile.path, file
          FileUtils.chmod 0644, file
          img_url = CGI.escape "https://#{ENV['MAIN_DOMAIN']}/#{file.gsub('public/','')}"
          begin
            response = MultiJson.load RestClient.post("https://www.filepicker.io/api/store/S3?key=#{ENV['FILEPICKER_API_KEY']}&url=#{img_url}", nil), :symbolize_keys => true
            if response[:size].to_i > 1500
              filepicker_url = response[:url]
            end
          rescue
          end
          FileUtils.rm_r dir, force: true
          break
        end
      end
    end

    @body.gsub!(/\n\n\n/, "\n\n \n\n") # allow double line breaks
    @body = unfold_paragraphs(@body) unless @from.include?('yahoo.com') # fix wrapped plain text, but yahoo messes this up
    @body = ActionController::Base.helpers.simple_format(@body) # format the email body coming in to basic HTML
    @body.gsub!(/\*(.+?)\*/i, '<b>\1</b>') # bold when bold needed
    @body.gsub!(/\[image\:\ Inline\ image\ [0-9]{1,2}\]/, '') # remove "inline image" text

    date = parse_subject_for_date(@subject)
    existing_entry = @user.existing_entry(date.to_s)

    inspiration_id = parse_body_for_inspiration_id(@raw_body)

    if existing_entry.present?
      existing_entry.body += "<hr>#{@body}"
      existing_entry.body = existing_entry.sanitized_body if @user.is_free?
      existing_entry.original_email_body = @raw_body
      existing_entry.inspiration_id = inspiration_id if inspiration_id.present?
      if existing_entry.image_url.present?
        img_url_cdn = filepicker_url.gsub("https://www.filepicker.io", ENV['FILEPICKER_CDN_HOST'])
        existing_entry.body += "<br><div class='pictureFrame'><a href='#{img_url_cdn}' target='_blank'><img src='#{img_url_cdn}/convert?fit=max&w=300&h=300&cache=true&rotate=:exif' alt='#{existing_entry.date.strftime("%b %-d")}'></a></div>"
      elsif filepicker_url.present?
        existing_entry.image_url = filepicker_url
      end
      begin
        existing_entry.save
      rescue
        existing_entry.body = existing_entry.body.force_encoding('iso-8859-1').encode('utf-8')
        existing_entry.original_email_body = existing_entry.original_email_body.force_encoding('iso-8859-1').encode('utf-8')
        existing_entry.save
      end
      track_ga_event('Merged')
    else

      begin
        entry = @user.entries.create!(
          date: date,
          body: @body,
          image_url: filepicker_url,
          original_email_body: @raw_body,
          inspiration_id: inspiration_id
        )
      rescue
        @body = @body.force_encoding('iso-8859-1').encode('utf-8')
        @raw_body = @raw_body.force_encoding('iso-8859-1').encode('utf-8')
        entry = @user.entries.create!(
          date: date,
          body: @body,
          image_url: filepicker_url,
          original_email_body: @raw_body,
          inspiration_id: inspiration_id
        )
      end

      entry.body = entry.sanitized_body if @user.is_free?
      entry.save
      track_ga_event('New')
    end

    @user.increment!(:emails_received)
    UserMailer.second_welcome_email(@user).deliver_later if @user.emails_received == 1 && @user.entries.count == 1
  end

  private

  def track_ga_event(action)
    Gabba::Gabba.new(ENV['GOOGLE_ANALYTICS_ID'], ENV['MAIN_DOMAIN']).event('Email Entry', action, @user.user_key) if ENV['GOOGLE_ANALYTICS_ID'].present?
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
    # Find the date from the subject "It's Sept 2 - How was your day?" and figure out the best year
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
    blank = false
    text  = ''
    body.split(/\n/).each do |line|
      if /\S/ !~ line
        text << "\n\n"
        blank = true
      else
        if line.length < 60 || /^(\s+|[*])/ =~ line
          text << (line.rstrip + "\n")
        else
          text << (line.rstrip + ' ')
        end
        blank = false
      end
    end
    text = text.gsub("\n\n\n", "\n\n")
    text
  end

  def parse_body_for_inspiration_id(raw_body)
    inspiration_id = nil
    begin
      Inspiration.without_ohlife_or_email_or_tips.each do |inspiration|
        if raw_body.include? inspiration.body
          inspiration_id = inspiration.id
          break
        end
      end
    rescue
    end
    inspiration_id
  end
end
