class ImportJob < ActiveJob::Base
  queue_as :default
 
  def perform(user_id,tmp_original_filename)
    user = User.find(user_id)
    dir = "public/ohlife_zips/#{user.user_key}"
    file = File.join(dir, tmp_original_filename)
    count = 0
    error_count = 0
    messages = []
    errors = []
    Zip::File.open(file) { |zip_file|
      zip_file.each { |f|
        f_path=File.join(dir, "unzipped", f.name)
        FileUtils.mkdir_p(File.dirname(f_path))
        zip_file.extract(f, f_path) unless File.exist?(f_path)
        if f.name =~ /^img_[12]{1}[90]{1}[0-9]{2}-[0-9]{2}-[0-9]{2}-0\.(jpe?g|gif|png)$/i
          date = f.name.scan(ImportController::SPLIT_AT_DATE_REGEX)[0]
          existing_entry = user.existing_entry(date.to_s)
          if existing_entry.present?
            img_url = CGI.escape "https://#{ENV['MAIN_DOMAIN']}/#{f_path.gsub("public/","")}"
            begin
              response = MultiJson.load RestClient.post("https://www.filepicker.io/api/store/S3?key=#{ENV['FILEPICKER_API_KEY']}&url=#{img_url}", nil), :symbolize_keys => true
              if response[:url].present?
                if existing_entry.image_url.present?
                  img_url_cdn = response[:url].gsub("https://www.filepicker.io", ENV['FILEPICKER_CDN_HOST'])
                  existing_entry.body += "<hr><div class='pictureFrame'><a href='#{img_url_cdn}' target='_blank'><img src='#{img_url_cdn}/convert?fit=max&w=300&h=300&cache=true&rotate=:exif' alt='#{existing_entry.date.strftime("%b %-d")}'></a></div>"
                else
                  existing_entry.image_url = response[:url]
                end
                existing_entry.save
                count+=1
              else
                error_count+=1
                errors << date
              end
            rescue
              error_count+=1
              errors << date
            end
          end
        end
      }
    }

    FileUtils.rm_r dir, :force => true
    
    messages << "Finished importing #{ActionController::Base.helpers.pluralize(count,'photo')}." if count > 0
    messages << "\rError importing #{ActionController::Base.helpers.pluralize(error_count,'photo')}:" if error_count > 0
    errors.each do |error|
      messages << error
    end

    ActionMailer::Base.mail(from: "Dabble Me <hello@#{ENV['SMTP_DOMAIN']}>",
                            to: "Dabble Me <hello@#{ENV['SMTP_DOMAIN']}>",
                            subject: "OhLife Image Import is complete for #{user.email}",
                            body: messages)
  end

end