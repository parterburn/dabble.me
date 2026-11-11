# frozen_string_literal: true

# A newsletter is a folder under newsletters/: a newsletter.yml naming who it
# goes to and which letter each person gets, plus one Markdown file per letter.
# See newsletters/README.md.
class Newsletter
  class Error < StandardError; end

  ROOT = Rails.root.join("newsletters")
  KEY_FORMAT = /\A[a-z0-9][a-z0-9-]*\z/

  Variant = Struct.new(:name, :min_entries_in_year, keyword_init: true)

  attr_reader :key

  def self.find(key, root: ROOT)
    raise Error, "Newsletter names are lowercase letters, digits and dashes: #{key.inspect}" unless key.to_s.match?(KEY_FORMAT)

    directory = Pathname(root).join(key.to_s)
    raise Error, "No newsletter at #{directory}" unless directory.join("newsletter.yml").file?

    new(key.to_s, directory)
  end

  def initialize(key, directory)
    @key = key
    @directory = directory
    @config = YAML.safe_load_file(directory.join("newsletter.yml")) || {}
    raise Error, "#{key}: audience must be \"pro\"" unless @config["audience"] == "pro"
    raise Error, "#{key}: list at least one variant" if variants.empty?
    raise Error, "#{key}: the last variant must have no conditions, so everyone gets a letter" if variants.last.min_entries_in_year
  end

  # The year whose entries are counted for `min_entries_in_year`.
  def year
    @config.fetch("year").to_i
  end

  def variants
    @variants ||= Array(@config["variants"]).map do |variant|
      Variant.new(name: variant.fetch("letter"), min_entries_in_year: variant["min_entries_in_year"])
    end
  end

  def letter(variant_name)
    @letters ||= {}
    @letters[variant_name] ||= Letter.new(@directory.join("#{variant_name}.md"))
  end

  # Everyone who should get this newsletter: PRO, not deleted, and still
  # taking product updates.
  def audience
    User.not_deleted.pro_only.where(send_updates: true)
  end

  def recipient?(user)
    audience.exists?(id: user.id)
  end

  # The first variant whose conditions the person meets.
  def variant_for(user, entries_in_year: entries_in_year(user))
    variants.find { |variant| variant.min_entries_in_year.nil? || entries_in_year >= variant.min_entries_in_year }.name
  end

  def entries_in_year(user)
    user.entries.unscope(:order).where(date: year_range).count
  end

  # { user_id => entries in the year } for many users in one query.
  def entry_counts(user_ids)
    Entry.unscoped.where(user_id: user_ids, date: year_range).group(:user_id).count
  end

  def delivered_user_ids
    NewsletterDelivery.where(newsletter: key).pluck(:user_id)
  end

  # What each letter is given to fill its {{placeholders}}.
  def values_for(user, entries_in_year: entries_in_year(user))
    host = ENV.fetch("MAIN_DOMAIN")
    {
      "first_name" => user.first_name_or_fallback("there"),
      "year" => year.to_s,
      "entry_count" => entries_in_year.to_s,
      "rewind_url" => "https://#{host}/rewind/#{year}",
      "write_url" => "https://#{host}/write",
      "settings_url" => "https://#{host}/settings?token=#{CGI.escape(user.email_settings_token)}"
    }
  end

  private

  def year_range
    Time.utc(year).all_year
  end
end
