# Queues the emails of a ServiceNotice, one job per person. Run in the
# background because there is one for every account with a journal.
class ServiceNoticeJob < ActiveJob::Base
  queue_as :default

  def perform(service_notice_id)
    ServiceNotice.find_by(id: service_notice_id)&.queue_deliveries!
  end
end
