class EmailProcessor
  def initialize(email)
    @token = pick_meaningful_recipient(email.to)
    @from = email.from[:email]
    @subject = email.subject
    @body = email.body
    @raw_body = email.raw_body
    @headers = email.headers
  end

  def process
    p "*"*100
    p "TO: #{@token}"
    p "FROM: #{@from}"
    p "SUBJECT: #{@subject}"
    p "BODY: #{@body}"
    p "RAW BODY: #{@raw_body}"
    p "HEADERS: #{@headers}"
    p "*"*100
    user = find_user_from_user_key(@token, @from)

    if user.present? && @body.present?
      date = parse_subject_for_date(@subject, user)
      existing_entry = user.existing_entry(date)

      if existing_entry.present?
        #existing entry exists, so add to it
        existing_entry.body += "<hr>#{@body}"
        existing_entry.inspiration_id = 2
        if existing_entry.save
          render :json => { "message" => "Existing entry could not save" }, :status => 200
        else
          render :json => { "message" => "Existing entry could not save" }, :status => 200
        end
      else
        #create new entry
        entry = user.entries.create!(
          date: date,
          body: @body,
          original_email_body: @raw_body,
          inspiration_id: 2
        )

        if entry.save
          render :json => { "message" => "Created new entry" }, :status => 200
        else
          render :json => { "message" => "Could not create new entry" }, :status => 200
        end      
      end

    else
      render :json => { "message" => "NO USER" }, :status => 200
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