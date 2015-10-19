class Payment < ActiveRecord::Base
  belongs_to :user
  validates :date, presence: true, valid_date: true
end
