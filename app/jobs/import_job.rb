class ImportJob < ActiveJob::Base
  queue_as :default

  IMAGE_FILENAME = /\Aimg_[12][90][0-9]{2}-[0-9]{2}-[0-9]{2}-0\.(jpe?g|gif|png)\z/i

  def perform(user_id, stored_path)
    user = User.find(user_id)
    zip_file = stored_path
    upload_dir = File.dirname(zip_file)
    count = 0
    error_count = 0
    messages = []
    errors = []

    file_path = File.join(upload_dir, "unzipped")
    FileUtils.mkdir_p(file_path)

    Zip::File.open(zip_file) do |zipfile|
      zipfile.each do |entry|
        basename = File.basename(entry.name)
        next unless basename.match?(IMAGE_FILENAME)
        next if entry.name.include?("..") || entry.directory?

        dest = File.join(file_path, basename)
        entry.extract(dest) { true }
      end
    end

    Dir.foreach(file_path) do |file|
      next unless file.match?(IMAGE_FILENAME)

      date = file.scan(ImportController::SPLIT_AT_DATE_REGEX)[0]
      existing_entry = user.existing_entry(date.to_s)
      if existing_entry.present? && existing_entry.image.blank?
        begin
          File.open(File.join(file_path, file), "rb") do |f|
            existing_entry.image = f
            if existing_entry.save
              count += 1
            else
              error_count += 1
              errors << file
            end
          end
        rescue StandardError
          error_count += 1
          errors << file
        end
      else
        error_count += 1
        errors << file
      end
    end

    messages << "Finished importing #{ActionController::Base.helpers.pluralize(count, 'photo')}." if count > 0
    messages << "\rError importing #{ActionController::Base.helpers.pluralize(error_count, 'photo')}:" if error_count > 0
    errors.each do |error|
      messages << error
    end

    ActionMailer::Base.mail(
      from: "Paul from Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>",
      to: user.email,
      subject: "Image Import is complete",
      body: messages.join("\n\n")
    ).deliver
  ensure
    ImportUploadStore.cleanup!(stored_path)
  end
end
