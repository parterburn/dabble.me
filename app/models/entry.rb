class Entry < ActiveRecord::Base
  include ActionView::Helpers::DateHelper
  include ActionView::Helpers::NumberHelper
  include ActiveModel::Validations
  include ApplicationHelper
  mount_uploader :image, ImageUploader

  WORDS_NOT_TO_COUNT = ['so', 'went', 'while', 's', 'amp', '-', 'p', 'br', 'div', 'img', 'span', 'the', 'of', 'and', 'a', 'to', 'in', 'is', 'that', 'it', 'was', 'for', 'on', 'are', 'as', 'with', 'at', 'be', 'this', 'have', 'from', 'or', 'had', 'by', 'but', 'not', 'what', 'all', 'were', 'when', 'can', 'said', 'there', 'use', 'an', 'each', 'which', 'do', 'how', 'if']

  belongs_to :user
  belongs_to :inspiration, optional: true

  validates :date, presence: true, valid_date: true
  validates :image, file_size: { less_than_or_equal_to: 20.megabytes },
                    file_content_type: { allow: ['image/gif', 'image/jpeg', 'image/jpg', 'application/octet-stream', 'image/png', 'image/heic'] }

  alias_attribute :entry, :body

  default_scope { order('date DESC') }

  scope :only_images, -> { where("image IS NOT null AND image != ''").order('date DESC') }
  scope :only_ohlife, -> { includes(:inspiration).where("inspirations.category = 'OhLife'").references(:inspiration).order('date DESC') }
  scope :only_email, -> { where("original_email_body IS NOT null").order('date DESC') }
  scope :only_spotify, -> { where.not("songs = '[]'").order('date DESC') }

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
      "<p><i>🎶 Songs: #{embeds.to_sentence}</i></p>".html_safe
    end
  end

  def time_ago_in_words_or_numbers(user)
    now_for_user = Time.now.in_time_zone(user.send_timezone)
    if self.date.day == 29 && self.date.month == 2 && now_for_user.year - 4 == self.date.year && now_for_user.day == 29 && now_for_user.month == 2
      "last leap day - exactly 4 years"
    else
      distance_of_time_in_words(self.date, now_for_user)
    end
  end

  def text_body
    Nokogiri::HTML.parse(ReverseMarkdown.convert(self.body, unknown_tags: :bypass))
  end

  def sanitized_body
    body_sanitized = ActionController::Base.helpers.sanitize self.body, tags: %w(br p)
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

  def hashtags
    h_body = ActionController::Base.helpers.strip_tags(ActionController::Base.helpers.simple_format(body.gsub("</p>","\n").gsub("<br>","\n").gsub("<br/>","\n")))
    return nil unless h_body.present?
    h_body.scan(/#([0-9]+[a-zA-Z_]+\w*|[a-zA-Z_]+\w*)/).map { |m| m[0] }
  end

  private

  def associate_inspiration
    self.inspiration = nil unless self.inspiration.in? Inspiration.without_imports_or_email_or_tips
  end

  def strip_out_base64
    if self.body.present?
      self.body = self.body.gsub("<a href=\"https://#{ENV['MAIN_DOMAIN']}/search?search%5Bterm%5D=\"></a>", "")
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
    grant = Base64.strict_encode64("#{ENV['SPOTIFY_API_CLIENT']}:#{ENV['SPOTIFY_API_SECRET']}")
    resp = RestClient.post("https://accounts.spotify.com/api/token", { grant_type: "client_credentials" }, { "Authorization": "Basic #{grant}" })
    oath_token = JSON.parse(resp.body)["access_token"]
    resp_song = RestClient.get("https://api.spotify.com/v1/tracks/#{track_id}", { "Authorization": "Bearer #{oath_token}" })
    song_data = JSON.parse(resp_song.body)
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
