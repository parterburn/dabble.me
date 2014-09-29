class Inspiration < ActiveRecord::Base
  has_many :entries 
  scope :without_ohlife, -> { where("category != 'OhLife'") }
end