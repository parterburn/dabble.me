class ImportTrailmixJob < ActiveJob::Base
  queue_as :default

  def perform(user_id, tmp_original_filename)
    @user = User.find(user_id)
    dir = "public/trailmix_zips/#{@user.user_key}"
    json_file = File.join(dir, tmp_original_filename)
    import_trailmix_entries(json_file)
  end

  def import_trailmix_entries(file)
    json_data = JSON.parse(File.read(file))
    errors = []
    i = 0;
    json_data.each do |entry|
      body = unfold_paragraphs(entry['body'])
      body = ActionController::Base.helpers.simple_format(body)
      body.gsub!(/\A(\<p\>\<\/p\>)/, '')
      body.gsub!(/(\<p\>\<\/p\>)\z/, '')
      date = entry['date']
      if @user.entries.where(date: date).exists?
        errors << "Entry already exists for #{date}"
        next
      end

      entry = @user.entries.create(date: date, body: body, inspiration_id: 68)
      unless entry.save
        errors << date
      end
    end

    errors_for_mailer = ""
    if errors.present?
      Sentry.capture_message("Errors while importing trailmix entries", level: :info, extra: { errors: errors })
      errors_for_mailer = "There were errors while importing the entries: #{errors.join(', ')}."
    end

    ActionMailer::Base.mail(from: "Paul from Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>",
      to: @user.email,
      subject: "Import of Trailmix.life entries is complete",
      content_type: "text/html",
      body: "Import of Trailmix.life entries is complete. You can view them at #{::Rails.application.routes.url_helpers.entries_url}. #{errors_for_mailer}").deliver_later
  rescue JSON::ParserError, NoMethodError => e
    Sentry.capture_exception(e)
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
end
