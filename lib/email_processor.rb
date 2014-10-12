require 'fileutils'

class EmailProcessor
  def initialize(email)
    @token = pick_meaningful_recipient(email.to)
    @from = email.from[:email].downcase
    @subject = email.subject
    if email.body.ascii_only?
      @body = EmailReplyParser.parse_reply(email.body)
    else
      @body = email.body
    end
    @raw_body = email.raw_body
    @attachments = email.attachments
  end

  def process
    user = find_user_from_user_key(@token, @from)

    if user.present? && @body.present?

      if @attachments.present?
        tmp = @attachments.first
        if tmp.present?
          if tmp.content_type =~ /^image\/png|jpe?g|gif$/i
            dir = FileUtils.mkdir_p("public/email_attachments/#{user.user_key}")
            file = File.join(dir, tmp.original_filename)
            FileUtils.mv tmp.tempfile.path, file
            FileUtils.chmod 0644, file
            img_url = CGI.escape "https://#{ENV['MAIN_DOMAIN']}/#{file.gsub("public/","")}"
            begin
              response = MultiJson.load RestClient.post("https://www.filepicker.io/api/store/S3?key=#{ENV['FILEPICKER_API_KEY']}&url=#{img_url}", nil), :symbolize_keys => true
              filepicker_url = response[:url]
            rescue
            end            
            
            FileUtils.rm_r dir, :force => true
          end
        end
      end

      @body = unfold_paragraphs(@body)
      @body = ActionController::Base.helpers.simple_format(@body) #format the email body coming in to basic HTML
      @body.gsub!(/\*([a-zA-Z0-9]+[a-zA-Z0-9 ]*[a-zA-Z0-9]+)\*/i, '<b>\1</b>') #bold when bold needed
      @body.gsub!(/\[image\:\ Inline\ image\ [0-9]{1,2}\]/, "") #remove "inline image" text

      date = parse_subject_for_date(@subject, user)
      existing_entry = user.existing_entry(date.to_s)

      inspiration_id = parse_body_for_inspiration_id(@raw_body)

      if existing_entry.present?
        existing_entry.body += "<hr>#{@body}"
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
      else

        begin
          entry = user.entries.create!(
            date: date,
            body: @body,
            image_url: filepicker_url,
            original_email_body: @raw_body,
            inspiration_id: inspiration_id
          )
        rescue
          @body = @body.force_encoding('iso-8859-1').encode('utf-8')
          @raw_body = @raw_body.force_encoding('iso-8859-1').encode('utf-8')
          entry = user.entries.create!(
            date: date,
            body: @body,
            image_url: filepicker_url,
            original_email_body: @raw_body,
            inspiration_id: inspiration_id
          )
        end

        entry.save
      end

      user.increment!(:emails_received)
      UserMailer.second_welcome_email(user).deliver if user.emails_received == 1 && user.entries.count == 1
    end

  end

  private

    def pick_meaningful_recipient(recipients)
      recipients.select {|k| k[:host] =~ /^(email|post)?\.?dabble\.me$/i }.first[:token]
    end

    def find_user_from_user_key(to_token, from_email)
      begin
        user = User.find_by_user_key(to_token)
      rescue JSON::ParserError => e
      end
      user.blank? ? User.find_by_email(from_email) : user
    end

    def parse_subject_for_date(subject,user)
      #Find the date from the subject "It's Sept 2 - How was your day?" and figure out the best year
      now = Time.now.in_time_zone(user.send_timezone)
      parsed_date = Time.parse(subject) rescue now
      dates = [ parsed_date, parsed_date.prev_year ]
      dates_to_use = []
      dates.each do |d|
        if Time.now + 7.days - d> 0
         dates_to_use << d
         end
      end
      dates_to_use.min_by { | d | ( d - now ).abs }.strftime("%Y-%m-%d")
    end

    def unfold_paragraphs(body)
      blank = false
      text  = ''
      body.split(/\n/).each do |line|
        if /\S/ !~ line
          text << "\n\n"
          blank = true
        else
          if /^(\s+|[*])/ =~ line
            text << (line.rstrip + "\n")
          else
            text << (line.rstrip + " ")
          end
          blank = false
        end
      end
      text = text.gsub("\n\n\n","\n\n")
      return text
    end

    def parse_body_for_inspiration_id(raw_body)
      inspiration_id = nil
      begin
        Inspiration.all.each do |inspiration|
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