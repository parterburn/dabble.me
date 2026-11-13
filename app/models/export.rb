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

  # The words of the search an export was made from. Kept only to name the
  # export; `scope` is what tells exports apart.
  encrypts :search_term

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
      "search:#{OpenSSL::HMAC.hexdigest('SHA256', key, normalized_search(search_term))}"
    elsif year.present?
      "year:#{year}"
    else
      "all"
    end
  end

  # Two searches share an export only when they match the same entries.
  # Matching ignores case, except that " OR " must be upper case to split a
  # search into alternatives (Entry::Matcher), so such a search keeps its case.
  def self.normalized_search(term)
    term = term.to_s.strip
    term.include?(" OR ") ? term : term.downcase
  end

  def self.describe(year: nil, search_term: nil, search: search_term.present?)
    if search_term.present?
      "Entries matching “#{search_term}”"
    elsif search
      "Entries matching a search"
    elsif year.present?
      "Entries from #{year}"
    else
      "All entries"
    end
  end

  # A download's name without its extension, saying what it holds:
  # dabble-me-2026-11-13, dabble-me-2021-2026-11-13,
  # dabble-me-search-coffee-2026-11-13.
  def self.file_stem(year: nil, search_term: nil, at: Time.current)
    subset = if search_term.present?
               ["search", search_term.to_s.parameterize.first(40).presence]
             else
               [year.presence]
             end
    ["dabble-me", *subset, at.strftime("%Y-%m-%d")].compact.join("-")
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

  # The year this export covers, when it covers just one.
  def year
    scope[/\Ayear:(\d{4})\z/, 1]
  end

  # "All entries", "Entries from 2021" or "Entries matching “coffee”".
  def description
    Export.describe(year: year, search_term: search_term, search: scope.start_with?("search:"))
  end

  def filename
    "#{Export.file_stem(year: year, search_term: search_term, at: created_at)}.zip"
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
