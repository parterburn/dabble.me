class Inspiration < ActiveRecord::Base
  IMPORT_CATEGORIES = ["OhLife", "Ahhlife", "Email", "Seed", "Trailmix", "Day One"].freeze

  has_many :entries
  scope :without_imports_or_email, -> { where("category NOT IN (?)", IMPORT_CATEGORIES) }
  scope :without_imports_or_email_or_tips, -> { without_imports_or_email.where("category != 'Tip'") }
  scope :writing_prompts, -> { where(category: "Question") }

  validates :category, presence: true
  validates :body, presence: true

  def inspired_by
    if IMPORT_CATEGORIES.include?(category)
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

  def self.random
    return nil unless (count = without_imports_or_email.count) > 0

    without_imports_or_email.offset(rand(count)).first
  end
end
