# Sends one person their copy of a ServiceNotice, at most once.
#
# As in NewsletterDeliveryJob, the delivery row is written before the email
# goes out, and the unique index on it turns a second attempt into a no-op.
# If sending fails the row is removed so a retry can try again.
class ServiceNoticeDeliveryJob < ActiveJob::Base
  queue_as :default

  def perform(service_notice_id, user_id)
    notice = ServiceNotice.find_by(id: service_notice_id)
    # They may have deleted their account or their entries since it was queued.
    user = ServiceNotice.recipients.find_by(id: user_id)
    return unless notice && user

    delivery = ServiceNoticeDelivery.create!(service_notice: notice, user: user, created_at: Time.current)

    begin
      ServiceNoticeMailer.export_reminder(user, message: notice.message, delivery: delivery).deliver_now
    rescue StandardError
      delivery.destroy
      raise
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
