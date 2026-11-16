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
# "Send me updates about Dabble Me" and the journal email schedule. Each
# notice carries its own link to stop further ones (ServiceNoticeDelivery).
class ServiceNotice < ActiveRecord::Base
  # The send was recorded but its emails could not be queued. Nothing went out.
  class NotQueued < StandardError; end

  MESSAGE_LIMIT = 2_000
  # How long after one notice before another can be sent.
  COOLDOWN = 24.hours
  # The pace emails go out at, the same as a newsletter's default.
  PER_MINUTE = 120
  # How many people one ServiceNoticeJob queues before handing on to the next.
  BATCH_SIZE = 500
  LINK = %r{https?://|www\.}i
  # Serializes sends, so two at once can't both pass the cooldown check.
  SEND_LOCK = 4_827_116

  belongs_to :sent_by, class_name: "User", optional: true
  has_many :deliveries, class_name: "ServiceNoticeDelivery", dependent: :delete_all

  # A browser sends each line break as two characters and counts it as one.
  before_validation { self.message = message.to_s.gsub(/\r\n?/, "\n").strip.presence }
  validates :message, length: { maximum: MESSAGE_LIMIT }
  validate :message_has_no_links

  # Everyone with at least one entry whose account isn't being deleted, apart
  # from anyone who lately asked for no more notices.
  def self.recipients
    User.not_deleted.where(id: Entry.select(:user_id)).where.not(id: ServiceNoticeDelivery.stopped_lately.select(:user_id))
  end

  # Why a notice can't be sent right now, or nil when one can.
  def self.blocker
    last = order(:created_at).last
    return unless last && last.created_at > COOLDOWN.ago

    "A notice went out on #{last.created_at.utc.strftime('%B %-d at %H:%M UTC')}. The next one can be sent 24 hours after it."
  end

  # Records the notice and queues its emails. Returns the notice, or nil when
  # one has gone out too recently. Raises NotQueued, having recorded nothing,
  # when the emails can't be queued.
  def self.send_to_everyone!(message:, sent_by:)
    notice = transaction do
      connection.execute("SELECT pg_advisory_xact_lock(#{SEND_LOCK})")
      next if blocker

      create!(message: message, sent_by: sent_by, recipients_count: recipients.count,
              sent_on: Time.current.utc.to_date, created_at: Time.current)
    end
    return unless notice

    begin
      ServiceNoticeJob.perform_later(notice.id)
    rescue StandardError => e
      # Take the record back, so the cooldown doesn't block a second try.
      notice.destroy
      raise NotQueued, e.message
    end
    notice
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Queues the emails for the next BATCH_SIZE people after `after_id`, in one
  # call to the queue, and returns their ids. `offset` is how many were queued
  # before them, which spaces the emails at PER_MINUTE.
  def queue_deliveries!(after_id: 0, offset: 0)
    user_ids = self.class.recipients.where("users.id > ?", after_id).order(:id).limit(BATCH_SIZE).pluck(:id)
    gap = 60.0 / PER_MINUTE
    jobs = user_ids.each_with_index.map do |user_id, index|
      ServiceNoticeDeliveryJob.new(id, user_id).set(wait: ((offset + index) * gap).seconds)
    end
    ActiveJob.perform_all_later(jobs) if jobs.any?
    user_ids
  end

  private

  # The email already links to the export page. A link typed here would turn
  # the notice into a way to send every writer anywhere.
  def message_has_no_links
    errors.add(:message, "can't contain links. The email already links to the export page.") if message.to_s.match?(LINK)
  end
end
