class Inspiration < ActiveRecord::Base
  has_many :entries 
  scope :without_ohlife_or_email, -> { where("category != 'OhLife'").where("category != 'Email'") }

  def inspired_by
    if ["OhLife", "Email"].include? category
      "Source: #{category}"
    else
      "Inspiration: #{category}"
    end
  end
end