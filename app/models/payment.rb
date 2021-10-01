class Payment < ActiveRecord::Base
  belongs_to :user, optional: true
  validates :date, presence: true, valid_date: true
end
