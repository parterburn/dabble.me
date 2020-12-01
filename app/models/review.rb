class Review < ApplicationRecord
  belongs_to :entry
  belongs_to :user

  validates :review_body, length: { maximum: 140 }
end
