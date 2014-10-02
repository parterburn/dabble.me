class EmailProcessor
  #skip_before_action :verify_authenticity_token, only: [:process]

  def self.process(email)
    user = find_user_from_user_key(email.to, email.from)

    if user.present? && email.body.present?
      date = parse_subject_for_date(email.subject, user)
      existing_entry = user.existing_entry(date)

      if existing_entry.present?
        #existing entry exists, so add to it
        existing_entry.body += "<hr>#{params['text']}"
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
          body: email.body,
          original_email_body: email.raw_body,
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

    def find_user_from_user_key(to_email, from_email)
      begin
        user_regex = /(u[0-9a-zA-Z]{10})/
        user_key = to_email.scan(user_regex)[0]
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