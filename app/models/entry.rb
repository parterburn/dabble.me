class Entry < ActiveRecord::Base
  include ActionView::Helpers::DateHelper
  include ActionView::Helpers::NumberHelper

  belongs_to :user
  belongs_to :inspiration

  before_validation :ensure_protocol

  validates :date, :presence => true, :valid_date => true
  validates :image_url, :valid_url => true
  validates :entry, presence: true

  alias_attribute :entry, :body
  
  default_scope { order('date DESC') }
  scope :only_images, -> { where("image_url IS NOT null").where("image_url != ''").order('date DESC') }
  scope :only_ohlife, -> { includes(:inspiration).where("inspirations.category = 'OhLife'").references(:inspiration).order('date DESC') }
  scope :only_email, -> { where("original_email_body IS NOT null").order('date DESC') }

  def date_format_long
    #Friday, Feb 3, 2014
    self.date.present? ? self.date.strftime("%A, %b %-d, %Y") : ""
  end

  def date_format_short(comma=",")
    #February 3, 2014
    self.date.present? ? self.date.strftime("%B %-d#{comma} %Y") : "July 3, 1985"
  end

  def date_day
    #Saturday
    self.date.present? ? self.date.strftime("%A") : "Noday?"
  end

  def time_ago_in_words_or_numbers(user)
    if self.date.day == 29 && self.date.month == 2 && Time.now.year - 4 == self.date.year
      "Last leap day (4 years ago)"
    elsif Time.now.in_time_zone(user.send_timezone).month == self.date.month && Time.now.in_time_zone(user.send_timezone).day == self.date.day && Time.now.in_time_zone(user.send_timezone).year - 1 == self.date.year
      "Exactly 1 year ago"
    else
      in_words = distance_of_time_in_words(self.date,Time.now.in_time_zone(user.send_timezone)).capitalize
      in_words.to_s.include?("Over") ? "Exactly #{number_with_delimiter((Time.now.in_time_zone(user.send_timezone) - self.date).to_i / 1.day)} days" : in_words
    end
  end

  def sanitized_body
    body_sanitized = ActionView::Base.full_sanitizer.sanitize(self.body)
    body_sanitized.gsub!(/\A(\n\n)/,"") if body_sanitized
    body_sanitized.gsub!(/(\<\n\n>)\z/,"") if body_sanitized
    body_sanitized
  end

  private

    def ensure_protocol # For urls
      self.image_url = self.image_url.strip.gsub(' ', "%20") unless image_url.blank?
      self.image_url = "http://#{image_url}" unless (/\Ahttp/ === image_url || image_url.blank?)
    end

end
