# Queues the emails of a ServiceNotice a batch at a time, then hands on to a
# copy of itself for the next batch. A retry repeats one batch at most, and the
# unique index on deliveries makes those repeats harmless.
class ServiceNoticeJob < ActiveJob::Base
  queue_as :default

  def perform(service_notice_id, after_id = 0, offset = 0)
    notice = ServiceNotice.find_by(id: service_notice_id)
    return unless notice

    user_ids = notice.queue_deliveries!(after_id: after_id, offset: offset)
    return if user_ids.size < ServiceNotice::BATCH_SIZE

    self.class.perform_later(service_notice_id, user_ids.last, offset + user_ids.size)
  end
end
