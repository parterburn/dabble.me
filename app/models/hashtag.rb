class Hashtag < ActiveRecord::Base
  belongs_to :user, optional: true

  validates :date, presence: true, valid_date: true
  # Encrypted in the database, so tags are compared and sorted in Ruby.
  encrypts :tag

  validates :tag, presence: true
  validate :tag_unique_for_user

  scope :with_dates, -> { where.not(date: [nil, ""]).order('date DESC') }

  # Case-insensitive, per user. A user has a handful of dated tags, so this
  # reads them rather than asking the database to compare encrypted values.
  def tag_unique_for_user
    return if tag.blank?

    others = Hashtag.where(user_id: user_id).where.not(id: id).pluck(:tag)
    errors.add(:tag, :taken) if others.any? { |other| other.to_s.casecmp?(tag) }
  end

  def date_format_short
    # February 3, 2014
    self.date.present? ? self.date.strftime("%B %-d, %Y") : nil
  end
end
