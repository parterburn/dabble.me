# Builds the ZIP for an Export, stores it privately and emails its owner a
# link. The link opens the app and needs a sign-in; the file itself is never
# attached or linked directly.
class ExportEntriesJob < ActiveJob::Base
  queue_as :default

  # What to export comes from the Export itself. `options` is only read for
  # jobs queued before exports recorded their own search.
  def perform(export_id, options = {})
    export = Export.find_by(id: export_id)
    return unless export&.preparing?

    options = options.with_indifferent_access
    year = export.year || options[:year]
    search_term = export.search_term.presence || options[:search_term]
    tempfile = Tempfile.new(["dabble-export", ".zip"], binmode: true)
    tempfile.close

    result = ExportArchive.new(entries_for(export.user, year, search_term), description: Export.describe(year: year, search_term: search_term)).write_to(tempfile.path)
    key = ExportStore.new.upload(ExportStore.key_for(export), tempfile.path)
    export.ready!(storage_key: key, byte_size: File.size(tempfile.path), entry_count: result.entry_count,
                  image_count: result.image_count, skipped_image_count: result.skipped_image_count)
    # Queued on its own, so trouble sending mail is retried there and never
    # undoes an export that is built and stored.
    UserMailer.export_ready(export).deliver_later
  rescue StandardError => e
    Sentry.capture_exception(e, extra: { export_id: export_id })
    if export && !export.reload.downloadable?
      export.update_columns(status: "failed")
      UserMailer.export_failed(export).deliver_later
    end
  ensure
    tempfile&.unlink
  end

  private

  def entries_for(user, year, search_term)
    if search_term.present?
      Search.new(term: search_term, user: user).entries
    elsif year.present?
      user.entries.where(date: Time.utc(year.to_i).all_year)
    else
      user.entries
    end
  end
end
