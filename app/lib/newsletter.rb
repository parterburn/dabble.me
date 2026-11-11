# frozen_string_literal: true

# A newsletter is a folder under newsletters/: a newsletter.yml naming who it
# goes to and the variants of the letter, plus the letter itself, letter.md.
# See newsletters/README.md.
class Newsletter
  class Error < StandardError; end

  ROOT = Rails.root.join("newsletters")
  KEY_FORMAT = /\A[a-z0-9][a-z0-9-]*\z/
  PLANS = %w[pro free].freeze

  Variant = Struct.new(:name, :plan, :min_entries_in_year, keyword_init: true)
  # Where a plan's letters are sent from. All nil means the app's defaults.
  Sender = Struct.new(:from, :reply_to, :mailgun_domain, keyword_init: true)

  attr_reader :key

  def self.find(key, root: ROOT)
    raise Error, "Newsletter names are lowercase letters, digits and dashes: #{key.inspect}" unless key.to_s.match?(KEY_FORMAT)

    directory = Pathname(root).join(key.to_s)
    raise Error, "No newsletter at #{directory}" unless directory.join("newsletter.yml").file?

    new(key.to_s, directory)
  end

  def self.plan_of(user)
    user.is_pro? ? "pro" : "free"
  end

  def initialize(key, directory)
    @key = key
    @directory = directory
    @config = YAML.safe_load_file(directory.join("newsletter.yml")) || {}
    @audiences = @config["audiences"] || {}
    check!
    letter
  end

  # The year whose entries are counted for `min_entries_in_year`.
  def year
    @config.fetch("year").to_i
  end

  # The plans this newsletter goes to: "pro", "free" or both.
  def plans
    @audiences.keys
  end

  def variants
    @variants ||= Array(@config["variants"]).map do |variant|
      Variant.new(name: variant.fetch("name"), plan: variant.fetch("plan"), min_entries_in_year: variant["min_entries_in_year"])
    end
  end

  def letter
    @letter ||= Letter.new(@directory.join("letter.md"), variants.map(&:name))
  end

  # Everyone on a plan who should get this newsletter: not deleted and still
  # taking product updates. Free accounts must also have shown some life
  # lately and never bounced, since mail to dead addresses is what gets a
  # sender blocked.
  def audience(plan)
    raise Error, "#{key} does not go to #{plan} accounts" unless plans.include?(plan)

    scope = User.not_deleted.where(send_updates: true)
    return scope.pro_only if plan == "pro"

    scope = scope.where("plan IS NULL OR plan NOT ILIKE '%pro%'").where(emails_bounced: [0, nil])
    months = @audiences.dig("free", "active_within_months")
    months ? active_since(scope, months.to_i.months.ago) : scope
  end

  def recipient?(user)
    plan = self.class.plan_of(user)
    plans.include?(plan) && audience(plan).exists?(id: user.id)
  end

  # The first variant for the person's plan whose conditions they meet.
  def variant_for(user, entries_in_year: entries_in_year(user))
    variant_name(self.class.plan_of(user), entries_in_year)
  end

  def variant_name(plan, entries_in_year)
    variants.find do |variant|
      variant.plan == plan && (variant.min_entries_in_year.nil? || entries_in_year >= variant.min_entries_in_year)
    end.name
  end

  def plan_of_variant(variant_name)
    variants.find { |variant| variant.name == variant_name }&.plan
  end

  def sender_for(plan)
    settings = @audiences[plan] || {}
    Sender.new(from: settings["from"], reply_to: settings["reply_to"], mailgun_domain: settings["mailgun_domain"])
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

  # What the letter is given to fill its {{placeholders}}.
  def values_for(user, entries_in_year: entries_in_year(user))
    host = ENV.fetch("MAIN_DOMAIN")
    {
      "first_name" => user.first_name_or_fallback("there"),
      "year" => year.to_s,
      "entry_count" => entries_in_year.to_s,
      "rewind_url" => "https://#{host}/rewind/#{year}",
      "write_url" => "https://#{host}/write",
      "subscribe_url" => "https://#{host}/subscribe",
      "settings_url" => "https://#{host}/settings?token=#{CGI.escape(user.email_settings_token)}"
    }
  end

  private

  def year_range
    Time.utc(year).all_year
  end

  # Signed in, or wrote an entry, since the given time.
  def active_since(scope, time)
    writers = Entry.unscoped.where(created_at: time..).select(:user_id)
    scope.where("users.current_sign_in_at >= :time OR users.last_sign_in_at >= :time OR users.id IN (#{writers.to_sql})", time: time)
  end

  def check!
    raise Error, "#{key}: list who it goes to under audiences (#{PLANS.join(', ')})" if plans.empty?
    raise Error, "#{key}: audiences can be #{PLANS.join(' or ')}, not #{(plans - PLANS).join(', ')}" if (plans - PLANS).any?
    raise Error, "#{key}: list at least one variant" if variants.empty?

    variants.each do |variant|
      raise Error, "#{key}: #{variant.name} is for #{variant.plan}, which is not under audiences" unless plans.include?(variant.plan)
    end
    plans.each do |plan|
      last = variants.select { |variant| variant.plan == plan }.last
      raise Error, "#{key}: #{plan} needs a variant" unless last
      raise Error, "#{key}: the last #{plan} variant must have no conditions, so everyone on #{plan} gets a letter" if last.min_entries_in_year
    end
  end
end
