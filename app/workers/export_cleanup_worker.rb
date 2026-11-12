# Deletes the files of exports past their expiry. A storage rule should also
# expire them, so a file never outlives a failure here.
class ExportCleanupWorker
  include Sidekiq::Job

  sidekiq_options retry: false, queue: :default

  # An export still "preparing" after this long was lost with its worker.
  STUCK_AFTER = 6.hours

  def perform
    Export.with_file.past_expiry.find_each do |export|
      export.expire!
    rescue StandardError => e
      Sentry.capture_exception(e, extra: { export_id: export.id })
    end

    Export.preparing.where(created_at: ..STUCK_AFTER.ago).update_all(status: "failed")
  end
end
