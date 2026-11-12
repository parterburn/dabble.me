# Builds the ZIP for an Export, stores it privately and emails its owner a
# link. The link opens the app and needs a sign-in; the file itself is never
# attached or linked directly.
class ExportEntriesJob < ActiveJob::Base
  queue_as :default

  def perform(export_id, options = {})
    export = Export.find_by(id: export_id)
    return unless export&.preparing?

    options = options.with_indifferent_access
    tempfile = Tempfile.new(["dabble-export", ".zip"], binmode: true)
    tempfile.close

    result = ExportArchive.new(entries_for(export.user, options)).write_to(tempfile.path)
    key = ExportStore.new.upload(ExportStore.key_for(export), tempfile.path)
    export.ready!(storage_key: key, byte_size: File.size(tempfile.path), entry_count: result.entry_count,
                  image_count: result.image_count, skipped_image_count: result.skipped_image_count)
    UserMailer.export_ready(export).deliver_now
  rescue StandardError => e
    export&.update_columns(status: "failed")
    Sentry.capture_exception(e, extra: { export_id: export_id })
    UserMailer.export_failed(export).deliver_now if export
  ensure
    tempfile&.unlink
  end

  private

  def entries_for(user, options)
    if options[:only_images]
      user.entries.only_images
    elsif options[:search_term].present?
      Search.new(term: options[:search_term], user: user).entries
    elsif options[:year].present?
      user.entries.where(date: Time.utc(options[:year].to_i).all_year)
    else
      user.entries
    end
  end
end
