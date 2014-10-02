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

  scope :only_images, -> { where("image_url IS NOT null") }

  def date_format_long
    #Friday, Feb 3, 2014
    self.date.present? ? self.date.strftime("%A, %b %-d, %Y") : ""
  end

  def date_format_short
    #February 3, 2014
    self.date.present? ? self.date.strftime("%B %-d, %Y") : "July 3, 1985"
  end

  def date_day
    #February 3, 2014
    self.date.present? ? self.date.strftime("%A") : "Noday?"
  end

  def time_ago_in_words_or_numbers
    in_words = time_ago_in_words(self.date).capitalize
    in_words.to_s.include?("Over") ? "Exactly #{number_with_delimiter((Time.zone.now - self.date).to_i / 1.day)} days" : in_words
  end

  private

    def ensure_protocol # For urls
      self.image_url = self.image_url.strip.gsub(' ', "%20") unless image_url.blank?
      self.image_url = "http://#{image_url}" unless (/\Ahttp/ === image_url || image_url.blank?)
    end

end
