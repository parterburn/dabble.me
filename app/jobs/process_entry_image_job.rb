class ProcessEntryImageJob < ActiveJob::Base
  queue_as :default

  def perform(entry_id, attachment_data:)
    entry = Entry.find_by(id: entry_id)
    return unless entry

    Tempfile.create(['entry_image', File.extname(attachment_data[:original_filename])]) do |tempfile|
      tempfile.binmode
      tempfile.write(Base64.strict_decode64(attachment_data[:data]))
      tempfile.rewind

      entry.image = tempfile
      entry.filepicker_url = nil if entry.filepicker_url == "https://d10r8m94hrfowu.cloudfront.net/uploading.png"
      entry.save
    end
  end
end
