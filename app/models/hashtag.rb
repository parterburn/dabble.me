class Hashtag < ActiveRecord::Base
  belongs_to :user, optional: true

  validates :date, presence: true, valid_date: true
  validates :tag, presence: true
  validates_uniqueness_of :tag, case_sensitive: false, scope: [:user_id]

  scope :with_dates, -> { where.not(date: [nil, ""]).order('date DESC') }

  def date_format_short
    # February 3, 2014
    self.date.present? ? self.date.strftime("%B %-d, %Y") : nil
  end
end
