class Inspiration < ActiveRecord::Base
  has_many :entries 
  scope :without_ohlife_or_email, -> { where("category != 'OhLife'").where("category != 'Email'") }
end