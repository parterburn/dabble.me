class Entry < ActiveRecord::Base
  validates :date, presence: true
  validates :body, presence: true             

  belongs_to :user
  belongs_to :inspiration

  before_validation :ensure_protocol
  validates :image_url, :valid_url => true

  private

    def ensure_protocol # For urls
      self.image_url = self.image_url.strip.gsub(' ', "%20") unless image_url.blank?
      self.image_url = "http://#{image_url}" unless (/\Ahttp/ === image_url || image_url.blank?)
    end  

end
