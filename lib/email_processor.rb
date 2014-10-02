class EmailProcessor
  def initialize(email)
    @token = pick_meaningful_recipient(email.to)
    @from = email.from[:email]
    @subject = email.subject
    @body = email.body
    @raw_body = email.raw_body
    @raw_html = email.raw_body
    @attachments = email.attachments
  end

  def process
    user = find_user_from_user_key(@token, @from)

    p "*"*100
    p @attachments
    p "*"*100

    if user.present? && @body.present?
      date = parse_subject_for_date(@subject, user)
      existing_entry = user.existing_entry(date)

      #format the email body coming in to basic HTML
      @body = ActionController::Base.helpers.simple_format(@body)
      @body.gsub!(/\*([a-zA-Z0-9]+[a-zA-Z0-9 ]*[a-zA-Z0-9]+)\*/i, "<b>#{$1}</b>")

      if existing_entry.present?
        #existing entry exists, so add to it
        existing_entry.body += "<hr>#{@body}"
        existing_entry.inspiration_id = 2
        existing_entry.save
      else
        #create new entry
        entry = user.entries.create!(
          date: date,
          body: @body,
          original_email_body: @raw_body,
          inspiration_id: 2
        )
        entry.save
      end
    end

  end

  private

    def pick_meaningful_recipient(recipients)
      recipients.select {|k| k[:host] =~ /^dabble\.me$/i }.first[:token]
    end

    def find_user_from_user_key(to_token, from_email)
      begin
        user_regex = /post\+(u[0-9a-zA-Z]{18})/
        user_key = to_token.scan(user_regex)[0]
        user = User.find_by_user_key(user_key)
      rescue JSON::ParserError => e
      end
      user.blank? ? User.find_by_email(from_email) : user
    end

    def parse_subject_for_date(subject,user)
      #Find the date from the subject "It's Sept 2 - How was your day?" and figure out the best year
      parse_day_regex = /((Jan|Feb|Marc?h?|Apri?l?|May|June?|July?|Aug|Sept?|Oct|Nov|Dec)\s([0-9]{1,2}))/i
      if subject.scan(parse_day_regex).present?
        date_stripped = subject.scan(parse_day_regex)[0][0]
        parsed_date = Time.parse(date_stripped)
        now = Time.now.in_time_zone(user.send_timezone)
        dates = [ parsed_date, parsed_date.prev_year ]
        dates_to_use = []
        dates.each do |d|
          if now - d> 0
           dates_to_use << d
           end
        end
        dates_to_use.min_by { | d | ( d - now ).abs }
      else
        Time.now.in_time_zone(user.send_timezone).strftime("%Y-%m-%d")
      end
    end

end