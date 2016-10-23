class Inspiration < ActiveRecord::Base
  has_many :entries
  scope :without_imports_or_email, -> { where("category != 'OhLife'").where("category != 'Ahhlife'").where("category != 'Email'") }
  scope :without_imports_or_email_or_tips, -> { without_imports_or_email.where("category != 'Tip'") }

  validates :category, presence: true
  validates :body, presence: true

  def inspired_by
    if ["OhLife", "Email", "Ahhlife"].include? category
      "Source: #{category}"
    elsif category == "Tip"
      "Tip"
    else
      "Inspiration: #{category}"
    end
  end

  def was_changed?(params)
    true if params[:inspiration][:category] != self.category || params[:inspiration][:body] != self.body
  end

end