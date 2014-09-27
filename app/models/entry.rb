class Entry < ActiveRecord::Base

  belongs_to :user
  belongs_to :inspiration

  before_validation :ensure_protocol

  validates :date, :presence => true, :valid_date => true
  validates :image_url, :valid_url => true  
  validates :entry, presence: true

  alias_attribute :entry, :body

  private

    def ensure_protocol # For urls
      self.image_url = self.image_url.strip.gsub(' ', "%20") unless image_url.blank?
      self.image_url = "http://#{image_url}" unless (/\Ahttp/ === image_url || image_url.blank?)
    end  

end
