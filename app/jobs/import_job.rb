class ImportJob < ActiveJob::Base
  queue_as :default

  def perform(user_id,tmp_original_filename)
    user = User.find(user_id)
    dir = "public/ohlife_zips/#{user.user_key}"
    zip_file = File.join(dir, tmp_original_filename)
    count = 0
    error_count = 0
    messages = []
    errors = []

    # unzip
    file_path=File.join(dir, "unzipped")
    FileUtils.mkdir_p(file_path)
    Zip::File.open(zip_file) do |zipfile|
      zipfile.each do |file|
        zipfile.extract(file, "#{file_path}/#{file.name}") { true }
      end
    end

    Dir.foreach("#{dir}/unzipped") do |file|
      if file =~ /^img_[12]{1}[90]{1}[0-9]{2}-[0-9]{2}-[0-9]{2}-0\.(jpe?g|gif|png)$/i
        date = file.scan(ImportController::SPLIT_AT_DATE_REGEX)[0]
        existing_entry = user.existing_entry(date.to_s)
        if existing_entry.present?
          img_url = CGI.escape "https://#{ENV['MAIN_DOMAIN']}/#{file_path.gsub("public/","")}/#{file}"
          begin
            existing_entry.remote_image_url = img_url if existing_entry.image.blank? && img_url.present?
            if existing_entry.save
              count+=1
            else
              # bad response from s3
              error_count+=1
              errors << file
            end
          rescue
            # could not upload to s3
            error_count+=1
            errors << file
          end
        else
          # no existing_entry
          error_count+=1
          errors << file
        end
      else
        # not the right type of file
        error_count+=1
        errors << file
      end
    end

    # Delete entire directory
    FileUtils.rm_r dir, :force => true

    messages << "Finished importing #{ActionController::Base.helpers.pluralize(count,'photo')}." if count > 0
    messages << "\rError importing #{ActionController::Base.helpers.pluralize(error_count,'photo')}:" if error_count > 0
    errors.each do |error|
      messages << error
    end

    ActionMailer::Base.mail(from: "Dabble Me Team <hello@#{ENV['MAIN_DOMAIN']}>",
                            to: user.email,
                            subject: "OhLife Image Import is complete",
                            body: messages.join("\n\n")).deliver
  end

end
