class Inspiration < ActiveRecord::Base
  has_many :entries
  scope :without_ohlife_or_email, -> { where("category != 'OhLife'").where("category != 'Email'") }

  validates :category, presence: true
  validates :body, presence: true

  CATEGORIES = ['Quote', 'Question', 'Email', 'OhLife']

  def inspired_by
    if ["OhLife", "Email"].include? category
      "Source: #{category}"
    else
      "Inspiration: #{category}"
    end
  end

  def was_changed?(params)
    true if params[:inspiration][:category] != self.category || params[:inspiration][:body] != self.body
  end

end