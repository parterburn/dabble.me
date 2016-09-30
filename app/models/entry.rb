class Entry < ActiveRecord::Base
  include ActionView::Helpers::DateHelper
  include ActionView::Helpers::NumberHelper
  include ActiveModel::Validations
  mount_uploader :image, ImageUploader

  belongs_to :user
  belongs_to :inspiration

  validates :date, presence: true, valid_date: true
  validates :entry, presence: true
  validates :image, file_size: { less_than: 10.megabytes }

  alias_attribute :entry, :body

  default_scope { order('date DESC') }

  scope :only_images, -> { where("image IS NOT null AND image != ''").order('date DESC') }
  scope :only_ohlife, -> { includes(:inspiration).where("inspirations.category = 'OhLife'").references(:inspiration).order('date DESC') }
  scope :only_email, -> { where("original_email_body IS NOT null").order('date DESC') }

  before_save :associate_inspiration
  after_save :check_image

  def date_format_long
    # Friday, Feb 3, 2014
    self.date.present? ? self.date.strftime("%A, %b %-d, %Y") : ""
  end

  def date_format_short(comma=",")
    # February 3, 2014
    self.date.present? ? self.date.strftime("%B %-d#{comma} %Y") : "July 3, 1985"
  end

  def date_day
    # Saturday
    self.date.present? ? self.date.strftime("%A") : "Noday?"
  end

  def hashtag_body
    h_body = self.body.gsub(/(<a[^>]*>.*?< ?\/a ?>)|(#[0-9]+\W)|(#[a-zA-Z0-9_]+)/) { "#{$1}#{$2}<a href='#{Rails.application.routes.url_helpers.search_url(host: ENV['MAIN_DOMAIN'], search: {term: $3})}'>#{$3}</a>" } if self.body.present?
    ActionController::Base.helpers.sanitize h_body, tags: %w(strong em a div span ul ol li b i img br p hr), attributes: %w(href style src)
  end

  def time_ago_in_words_or_numbers(user)
    now_for_user = Time.now.in_time_zone(user.send_timezone)
    if self.date.day == 29 && self.date.month == 2 && now_for_user.year - 4 == self.date.year && now_for_user.day == 29 && now_for_user.month == 2
      "last leap day - exactly 4 years"
    elsif now_for_user.month == self.date.month && now_for_user.day == self.date.day && now_for_user.year - 1 == self.date.year
      "exactly 1 year"
    elsif now_for_user.month - 1 == self.date.month && now_for_user.day == self.date.day && now_for_user.year == self.date.year
      "exactly 1 month"
    elsif now_for_user.month == self.date.month && now_for_user.day - 7 == self.date.day && now_for_user.year == self.date.year
      "exactly 1 week"
    else
      in_words = distance_of_time_in_words(self.date,now_for_user)
      in_words.to_s.include?("over") ? "exactly #{number_with_delimiter((now_for_user - self.date).to_i / 1.day)} days" : in_words
    end
  end

  def sanitized_body
    body_sanitized = ActionView::Base.full_sanitizer.sanitize(self.body)
    body_sanitized.gsub!(/\A(\n\n)/,"") if body_sanitized
    body_sanitized.gsub!(/(\<\n\n>)\z/,"") if body_sanitized
    body_sanitized
  end

  def image_url_cdn
    if image.present?
      image.url
    end
  end

  def exactly_past_years(user)
    if user.present? && self.date.present?
      now_with_timezone = Time.now.in_time_zone(user.send_timezone)
      now_with_timezone.month == self.date.month &&
        now_with_timezone.day == self.date.day &&
        now_with_timezone.year != self.date.year
    end
  end

  private

  def associate_inspiration
    self.inspiration = nil unless self.inspiration.in? Inspiration.without_ohlife_or_email_or_tips
  end

  def check_image
    if image.present? && image_changed?
      c_image = Clarifai::Rails::Detector.new(image_url_cdn).image
      if c_image.tags_with_percent[:nsfw] > 0.15
        Rails.logger.warn("NSFW Flagged (#{(c_image.tags_with_percent[:nsfw]*100).round}%) — USER: #{entry.user.email} ENTRY: #{entry.id} URL: #{entry.image_url_cdn}")
      end
    end
  end

end
