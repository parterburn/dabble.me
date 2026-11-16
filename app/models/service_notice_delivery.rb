# One person's copy of a ServiceNotice. The unique index on it is what keeps a
# retried job from emailing someone twice.
#
# Each copy links to a page where the person can stop further notices
# (NoticeStopsController). That is recorded here, and holds for STOP_PERIOD:
# long enough to cover the reminders of one shutdown, short enough that an
# unrelated notice years later still reaches them.
class ServiceNoticeDelivery < ActiveRecord::Base
  STOP_PERIOD = 1.year

  belongs_to :service_notice
  belongs_to :user

  scope :stopped_lately, -> { where(stopped_at: STOP_PERIOD.ago..) }

  # The token in the email's stop link. It names this copy, so it can't be
  # used to stop anyone else's.
  def stop_token
    signed_id(purpose: :stop_notices)
  end

  def self.find_by_stop_token(token)
    find_signed(token.to_s, purpose: :stop_notices)
  end

  def stop!
    update_columns(stopped_at: Time.current) unless stopped_at
  end
end
