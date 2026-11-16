# The one email an admin can send to everyone with a journal: a reminder to
# export it, with an optional message from the admin on top. Sent from
# /admin/notices, for a shutdown, a change of operator or anything else every
# writer has to hear about.
#
# It is narrow on purpose, because it reaches every writer from the real
# domain: the subject and body are fixed (ServiceNoticeMailer), the admin's
# message is plain text with no links, the audience can't be chosen, and at
# most one goes out a day.
#
# It is a notice about a person's data, not a newsletter, so it ignores
# "Send me updates about Dabble Me" and the journal email schedule.
class ServiceNotice < ActiveRecord::Base
  MESSAGE_LIMIT = 2_000
  # How long after one notice before another can be sent.
  COOLDOWN = 24.hours
  # The pace emails go out at, the same as a newsletter's default.
  PER_MINUTE = 120
  LINK = %r{https?://|www\.}i

  belongs_to :sent_by, class_name: "User", optional: true
  has_many :deliveries, class_name: "ServiceNoticeDelivery", dependent: :delete_all

  before_validation { self.message = message.to_s.strip.presence }
  validates :message, length: { maximum: MESSAGE_LIMIT }
  validate :message_has_no_links

  # Everyone with at least one entry whose account isn't being deleted.
  def self.recipients
    User.not_deleted.where(id: Entry.select(:user_id))
  end

  # Why a notice can't be sent right now, or nil when one can.
  def self.blocker
    last = order(:created_at).last
    return unless last && last.created_at > COOLDOWN.ago

    "A notice went out on #{last.created_at.utc.strftime('%B %-d at %H:%M UTC')}. The next one can be sent 24 hours after it."
  end

  # Records the notice and queues its emails. Returns the notice, or nil when
  # one has already gone out today.
  def self.send_to_everyone!(message:, sent_by:)
    notice = create!(message: message, sent_by: sent_by, recipients_count: recipients.count,
                     sent_on: Time.current.utc.to_date, created_at: Time.current)
    ServiceNoticeJob.perform_later(notice.id)
    notice
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Queues one job per person, spaced so at most PER_MINUTE go out a minute.
  def queue_deliveries!
    gap = 60.0 / PER_MINUTE
    index = 0
    self.class.recipients.in_batches(of: 500) do |batch|
      batch.pluck(:id).each do |user_id|
        ServiceNoticeDeliveryJob.set(wait: (index * gap).seconds).perform_later(id, user_id)
        index += 1
      end
    end
    index
  end

  private

  # The email already links to the export page. A link typed here would turn
  # the notice into a way to send every writer anywhere.
  def message_has_no_links
    errors.add(:message, "can't contain links. The email already links to the export page.") if message.to_s.match?(LINK)
  end
end
