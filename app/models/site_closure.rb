# The closing of Dabble Me, announced by an admin at /admin/closing. There is
# one row or none: none means the service is open.
#
# From the day it is announced, nobody new can sign up or start paying, and
# every page carries a banner with the closing date and a link to export.
# From the closing date, the journal and the marketing pages give way to the
# goodbye page and the journal emails stop. People can still sign in, export,
# and delete their account. Nothing here deletes any data: that is done by
# hand, after DELETION_DELAY.
class SiteClosure < ActiveRecord::Base
  # How long after closing the journals are kept, as the pages tell people.
  DELETION_DELAY = 30.days
  # What an admin types to announce a closing.
  CONFIRMATION = "CLOSE"

  belongs_to :announced_by, class_name: "User", optional: true

  validates :closes_on, presence: true
  validate :closes_today_or_later, if: :closes_on_changed?

  def self.current
    first
  end

  def self.announced?
    current.present?
  end

  def self.closed?
    current&.closed? || false
  end

  # Announces a closing, or moves the date of the one already announced.
  def self.announce(closes_on:, announced_by:)
    closure = current || new
    closure.update(closes_on: closes_on, announced_by: announced_by)
    closure
  rescue ActiveRecord::RecordNotUnique
    current
  end

  def self.reopen!
    delete_all
  end

  def closed?
    Date.current >= closes_on
  end

  # The day after which journals are deleted.
  def deletes_on
    closes_on + DELETION_DELAY
  end

  private

  def closes_today_or_later
    errors.add(:closes_on, "can't be in the past") if closes_on && closes_on < Date.current
  end
end
