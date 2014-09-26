class Entry < ActiveRecord::Base
  validates :date, presence: true
  validates :body, presence: true             

  belongs_to :user
  belongs_to :inspiration

end
