# One person's copy of a ServiceNotice. The unique index on it is what keeps a
# retried job from emailing someone twice.
class ServiceNoticeDelivery < ActiveRecord::Base
  belongs_to :service_notice
  belongs_to :user
end
