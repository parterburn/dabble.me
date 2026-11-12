# One export of a person's entries. The ZIP lives in private storage
# (ExportStore) until it expires; the app hands out a short-lived download
# link only to its owner, signed in.
class Export < ActiveRecord::Base
  LIFETIME = 7.days
  # How long a download link from the app works once handed out.
  LINK_LIFETIME = 5.minutes
  # One export of the same thing (everything, a year, a search) per person
  # in this long; asking again downloads the last one. A failed one doesn't
  # count.
  LIMIT_PERIOD = 12.hours
  # However varied the requests, this many per person an hour and no more.
  HOURLY_LIMIT = 10

  belongs_to :user

  has_secure_token :token, length: 36

  scope :preparing, -> { where(status: "preparing") }
  scope :with_file, -> { where.not(storage_key: nil) }
  scope :within_limit, -> { where(created_at: LIMIT_PERIOD.ago..).where.not(status: "failed") }
  scope :past_expiry, -> { where(expires_at: ..Time.current) }

  before_destroy :delete_file

  # What an export of this year or search holds, as stored in `scope`:
  # "all", "year:2021" or "search:<digest>". The digest tells two searches
  # apart without storing the words, and is keyed so it can't be reversed by
  # guessing words against a copy of the database.
  def self.scope_for(year: nil, search_term: nil)
    if search_term.present?
      key = Rails.application.key_generator.generate_key("export search scope", 32)
      "search:#{OpenSSL::HMAC.hexdigest('SHA256', key, search_term.to_s.strip.downcase)}"
    elsif year.present?
      "year:#{year}"
    else
      "all"
    end
  end

  def to_param
    token
  end

  def preparing?
    status == "preparing"
  end

  def failed?
    status == "failed"
  end

  # Ready, not expired, and the file is still there.
  def downloadable?
    status == "ready" && storage_key.present? && expires_at.present? && expires_at.future?
  end

  def filename
    "dabble-me-export-#{created_at.strftime('%Y-%m-%d')}.zip"
  end

  def ready!(storage_key:, byte_size:, entry_count:, image_count:, skipped_image_count:)
    update!(status: "ready", storage_key: storage_key, byte_size: byte_size, entry_count: entry_count,
            image_count: image_count, skipped_image_count: skipped_image_count, expires_at: LIFETIME.from_now)
  end

  def downloaded!
    update_columns(downloaded_at: Time.current, download_count: download_count + 1)
  end

  # Deletes the file and keeps the row, so the link can say it expired.
  def expire!
    delete_file
    update!(status: "expired", storage_key: nil)
  end

  private

  def delete_file
    ExportStore.new.delete(storage_key) if storage_key.present?
  end
end
