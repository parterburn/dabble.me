class Hashtag < ActiveRecord::Base
  belongs_to :user, optional: true

  validates :date, presence: true, valid_date: true
  validates :tag, presence: true
  validates_uniqueness_of :tag, scope: [:user_id]

  scope :with_dates, -> { where.not(date: [nil, ""]).order('date DESC') }
end
