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
  scope :only_spotify, -> { where.not(songs: "[]").order('date DESC') }

  before_save :associate_inspiration
  before_save :strip_out_base64
  before_save :find_songs
  after_save :check_image

  def date_format_long
    # Friday, Feb 3, 2014
    self.date.present? ? self.date.strftime("%A, %b %-d, %Y") : ""
  end

  def date_format_short
    # February 3, 2014
    self.date.present? ? self.date.strftime("%B %-d, %Y") : "July 3, 1985"
  end

  def date_day
    # Saturday
    self.date.present? ? self.date.strftime("%A") : "Noday?"
  end

  def hashtag_body
    return nil unless self.body.present?
    h_body = Rinku.auto_link(self.body, :all, 'target="_blank"')
    h_body.gsub!(/(<a[^>]*>.*?< ?\/a ?>)|(#[0-9]+\W)|(#[a-zA-Z0-9_]+)/) { "#{$1}#{$2}<a href='#{Rails.application.routes.url_helpers.search_url(host: ENV['MAIN_DOMAIN'], search: {term: $3})}'>#{$3}</a>" }
    ActionController::Base.helpers.sanitize h_body, tags: %w(strong em a div span ul ol li b i img br p hr), attributes: %w(href style src target)
  end

  def spotify_embed
    embeds = []
    self.songs.each do |song|
      embeds << "<p class='spotify'><iframe src='https://open.spotify.com/embed?uri=spotify:track:#{song['spotify_id']}' width='100%' height='80' frameborder='0' allowtransparency='true'></iframe></p>"
    end
    embeds.join.html_safe
  end

  def spotify_track_names
    embeds = []
    self.songs.each do |song|
      embeds << "<a href=\"https://open.spotify.com/track/#{song['spotify_id']}\">#{song['artists'].to_sentence} - #{song['title']}</a>&nbsp;"
    end
    if embeds.present?
      "<p><i>Songs: #{embeds.to_sentence}</i></p>".html_safe
    end
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

  def next
    self.user.entries.where("date > ?", date).sort_by(&:date).first
  end

  def previous
    self.user.entries.where("date < ?", date).sort_by(&:date).last
  end

  private

  def associate_inspiration
    self.inspiration = nil unless self.inspiration.in? Inspiration.without_imports_or_email_or_tips
  end

  def strip_out_base64
    if self.body.present?
      self.body = self.body.gsub(/src=\"data\:image\/(jpeg|png)\;base64\,.*\"/, "src=\"\"")
      self.body = self.body.gsub(/url\(data\:image\/(jpeg|png)\;base64\,.*\)/, "url()")
    end
    if self.original_email_body.present?
      self.original_email_body = self.original_email_body.gsub(/src=\"data\:image\/(jpeg|png)\;base64\,.*\"/, "src=\"\"")
      self.original_email_body = self.original_email_body.gsub(/url\(data\:image\/(jpeg|png)\;base64\,.*\)/, "url()")
    end
  end

  def find_songs
    self.songs = []
    if self.body.present?
      matches = self.body.scan(/open\.spotify\.com\/track\/(\w+)/)
      matches.uniq.each do |match|
        if (spotify_name = get_spotify_info_from_track_id(match.first)).present?
          self.songs << { spotify_id: match.first, artists: spotify_name.first, title: spotify_name.last }
        end
      end
    end
  end

  def get_spotify_info_from_track_id(track_id)
    uri = URI("https://api.spotify.com/v1/tracks/#{track_id}")
    req = Net::HTTP::Get.new(uri)

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http|
      http.request(req)
    }
    song_data = JSON.parse(res.body)
    unless song_data['error'].present?
      [song_data['artists'].map { |a| a['name'] }, song_data['name']]
    else
      nil
    end
  end

  def check_image
    if image.present? && image_changed? && ENV['CLARIFAI_V2_API_KEY'].present?
      begin
        url = "https://api.clarifai.com/v2/models/#{ENV['CLARIFAI_V2_NSFW_MODEL']}/outputs"
        headers = {"Authorization" => "Key #{ENV['CLARIFAI_V2_API_KEY']}", "Content-Type" => "application/json"}
        payload = { inputs: [ { data: { image: { url: image_url_cdn } } } ] }.to_json
        res = JSON.parse(RestClient.post(url, payload, headers))
        nsfw_percent = res.try(:[], 'outputs')&.first.try(:[], 'data').try(:[], 'concepts')&.second.try(:[], 'value')
        if nsfw_percent >= 0.15
          Rails.logger.warn("NSFW Flagged (#{(nsfw_percent*100).round}%) — USER: #{user.email} ENTRY: #{id} IMAGE: #{image_url_cdn}")
        end
      rescue => e
        Rails.logger.warn("Clarifai Error: #{e}")
      end
    end
  end

end
