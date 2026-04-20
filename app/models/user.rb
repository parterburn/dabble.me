class User < ActiveRecord::Base
  include RandomizedField
  include User::XOauth

  VALID_EMAIL_REGEX = /\A[A-Z0-9._%'+-]+@[A-Z0-9.-]+\.[A-Z]{2,63}\z/i
  validates :email, format: { with: VALID_EMAIL_REGEX }, allow_blank: true

  # Include default devise modules. Others available are:
  # :confirmable, :timeoutable and :omniauthable, :lockable
  devise :otp_authenticatable, :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  randomized_field :user_key, length: 18 do |slug_value|
    "u#{slug_value}"
  end

  has_many :entries, dependent: :destroy
  has_many :hashtags, dependent: :destroy
  has_many :payments
  has_many :webauthn_credentials, dependent: :destroy
  has_many :x_bookmarks, dependent: :destroy

  accepts_nested_attributes_for :hashtags, allow_destroy: true, :reject_if => proc { |att| att[:tag].blank? || att[:date].blank? }

  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :subscribed_to_emails, -> { not_deleted.where.not(frequency: []).where.not(frequency: nil) }
  scope :not_just_signed_up, -> { where("created_at < (?)", DateTime.now - 18.hours) }
  scope :daily_emails, -> { where(frequency: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]) }
  scope :with_entries, -> { includes(:entries).where("entries.id > 0").references(:entries) }
  scope :without_entries, -> { includes(:entries).where("entries.id IS null").references(:entries) }
  scope :free_only, -> { where("plan ILIKE '%free%' OR plan IS null") }
  scope :pro_only, -> { where("plan ILIKE '%pro%'") }
  scope :monthly, -> { where("plan ILIKE '%monthly%'") }
  scope :yearly, -> { where("plan ILIKE '%yearly%'") }
  scope :forever, -> { where("plan ILIKE '%forever%'") }
  scope :payhere_only, -> { where("plan ILIKE '%payhere%'") }
  scope :gumroad_only, -> { where("plan ILIKE '%gumroad%'") }
  scope :paypal_only, -> { where("plan ILIKE '%paypal%'") }
  scope :not_forever, -> { where("plan NOT ILIKE '%forever%'") }
  scope :referrals, -> { where("referrer IS NOT null") }

  after_commit :notify_stripe

  before_save { email&.gsub!(",",".")&.gsub!(".@", "@")&.downcase! }
  before_save { send_timezone.gsub!("&amp;", "&") }
  before_save :disable_mcp_without_strong_auth
  after_commit on: :update do
    restrict_free_frequency
  end
  after_commit :send_welcome_email, on: :create

  def full_name
    "#{first_name} #{last_name}" if first_name.present? || last_name.present?
  end

  def abbreviated_name
    "#{first_name} #{last_name.first&.upcase}"
  end

  def cleaned_to_address
    "#{full_name.gsub(/[^\w\s-]/i, '') if full_name.present?} <#{email}>"
  end

  def full_name_or_email
    first_name.present? ? "#{first_name} #{last_name}" : email
  end

  def first_name_or_fallback(fallback='there')
    first_name.present? ? "#{first_name}" : fallback
  end

  def frequencies
    frequency.to_sentence
  end

  def random_entry(entry_date=nil)
    if entry_date.present?
      entry_date = Date.parse(entry_date.to_s)

      if (entry_date.day == 29 && entry_date.month == 2) && (exact_last_leap_year_entry = random_entries.where('extract(month from date) = ? AND extract(day from date) = ? AND extract(year from date) = ?', 2, 29, entry_date.last_year.year).first).present?
        exact_last_leap_year_entry
      elsif way_back_past_entries && (exact_years_back_entry = random_entries.where('extract(month from date) = ? AND extract(day from date) = ? AND extract(year from date) != ?', entry_date.month, entry_date.day, entry_date.year).sample)
        exact_years_back_entry
      elsif (exactly_last_year_entry = random_entries.where(date: entry_date.last_year).first)
        exactly_last_year_entry
      elsif (emails_sent % 3 == 0) && (exactly_30_days_ago = random_entries.where(date: entry_date.last_month).first)
        exactly_30_days_ago
      elsif random_entries.count < 50 && (emails_sent % 5 == 0) && (exactly_7_days_ago = random_entries.where(date: entry_date - 7.days).first)
        exactly_7_days_ago
      elsif way_back_past_entries && (emails_sent % 2 == 0) && random_entries.where('date < (?)', entry_date.last_year).count > 30
        random_entries.where('date < (?)', entry_date.last_year).sample # grab entry way back
      else
        way_back_past_entries ? self.random_entry : random_entries.where("date > (?)", 1.year.ago).sample
      end
    else
      random_entries.sample
    end
  end

  def existing_entry(selected_date)
    selected_date = Date.parse(selected_date.to_s)
    entries.where(date: selected_date).first
  rescue
    nil
  end

  def can_ai?
    ai_opt_in?
  end

  def mcp_security_requirements_met?
    otp_enabled? || webauthn_credentials.exists?
  end

  def mcp_available?
    is_pro? && !deletion_pending? && mcp_enabled? && mcp_token_digest.present? && mcp_security_requirements_met?
  end

  def generate_mcp_token!
    raise ArgumentError, 'MCP access requires a PRO subscription.' unless is_pro?
    raise ArgumentError, 'MCP access requires a passkey or two-factor authentication.' unless mcp_security_requirements_met?

    raw_token = "dmcp_#{SecureRandom.urlsafe_base64(48)}"

    update!(
      mcp_enabled: true,
      mcp_token_digest: self.class.digest_mcp_token(raw_token),
      mcp_token_generated_at: Time.current
    )

    raw_token
  end

  def revoke_mcp_token!
    update!(
      mcp_enabled: false,
      mcp_token_digest: nil,
      mcp_token_generated_at: nil,
      mcp_last_used_at: nil
    )
  end

  def mark_mcp_token_used!
    update_column(:mcp_last_used_at, Time.current)
  end

  def deletion_pending?
    deleted_at.present?
  end

  # Devise: prevent login if account is pending deletion
  def active_for_authentication?
    super && !deletion_pending?
  end

  # Devise: custom message for pending deletion
  def inactive_message
    deletion_pending? ? :account_pending_deletion : super
  end

  def is_pro?
    plan_name == 'Dabble Me PRO'
  end

  def is_free?
    !is_pro?
  end

  def plan_name
    if plan && plan.match(/pro/i)
      'Dabble Me PRO'
    else
      'Dabble Me Free'
    end
  end

  # PRO Monthly PayHere
  # PRO Yearly PayHere
  def plan_frequency
    if plan && plan.match(/monthly/i)
      'Monthly'
    elsif plan && plan.match(/yearly/i)
      'Yearly'
    end
  end

  def plan_type_unlinked
    if plan && plan.match(/payhere/i)
      "Stripe"
    elsif plan && plan.match(/gumroad/i)
      "Gumroad"
    elsif plan && plan.match(/paypal/i)
      'PayPal'
    end
  end

  def plan_type
    if plan && plan.match(/payhere/i)
      "<a href='/billing'>Stripe</a>"
    elsif plan && plan.match(/gumroad/i)
      "<a href='https://gumroad.com/login' target='_blank'>Gumroad</a>"
    elsif plan && plan.match(/paypal/i)
      'PayPal'
    end
  end

  def plan_details
    p = plan_name
    p = p + ' ' + plan_frequency if plan_frequency.present?
    p
  end

  def days_since_last_post
    if last_post = entries.where("date < ?", Time.now).first
      (Time.now.to_date - last_post.date.to_date).to_i
    else
      nil
    end
  end

  def past_filter_entry_ids
    if (filters = self.past_filter).present?
      filter_names = filters.split(',').map(&:strip)
      cond_text = filter_names.map{|w| "LOWER(entries.body) like ?"}.join(" OR ")
      cond_values = filter_names.map{|w| "%#{w}%"}
      self.entries.where(cond_text, *cond_values).pluck(:id)
    end
  end

  def random_entries
    @random_entries ||= entries.where.not(id: past_filter_entry_ids)
  end

  def remember_me
    super.present? ? super : true
  end

  def any_hashtags?
    original_hashtags.any?
  end

  alias_method :original_hashtags, :hashtags
  def hashtags
    @hashtags_list ||= begin
      existing_tags = original_hashtags.pluck(:tag).map(&:downcase)
      used_hashtags(entries.limit(100), true).first(5).each do |h|
        next if existing_tags.include?(h.downcase)

        original_hashtags.build(tag: h)
        existing_tags << h.downcase
      end
      original_hashtags.build
      original_hashtags.to_a
    end
  end

  def hashtags_attributes=(value)
    original_hashtags.destroy_all
    (0..value.count-1).each do |i|
      record = value[i.to_s]
      if record["tag"].present? && record["date"].present?
        original_hashtags.create(tag: record["tag"], date: Date.parse(record["date"]))
      end
    end
  end

  def used_hashtags(entries, unique)
    hashtags = entries.where("entries.body ~ '(#[a-zA-Z0-9_]+)'").map(&:hashtags).reject(&:blank?).flatten.map(&:downcase)
    if unique
      hashtags.group_by{|x| x}.sort_by{|k, v| -v.size}.map(&:first)
    else
      hashtags
    end
  end

  def send_time_in_mt
    send_time.hour + (ActiveSupport::TimeZone["America/Denver"].formatted_offset(false).to_i - ActiveSupport::TimeZone[send_timezone].formatted_offset(false).to_i)/100
  end

  def writing_streak
    @writing_streak ||= begin
      streak = 0
      # Get all entry dates for the user, sorted descending
      entry_dates = entries.pluck(:date).compact.map(&:to_date).uniq.sort.reverse

      if entry_dates.any?
        today = Time.current.in_time_zone(send_timezone).to_date

        # Start checking from today or the latest entry date if it's recent
        current_date = entry_dates.first

        # If the latest entry is older than yesterday, the streak is broken (unless it's today/yesterday)
        if current_date >= today - 1.day
          entry_dates.each do |date|
            if date == current_date
              streak += 1
              current_date -= 1.day
            else
              break
            end
          end
        end
      end
      streak
    end
  rescue StandardError => e
    Sentry.capture_exception(e, extra: { user_id: id })
    0
  end

  def has_active_stripe_subscription?
    return nil unless stripe_id.present?
    subscriptions = Stripe::Subscription.list(customer: stripe_id)
    subscriptions.any? { |subscription| %w[trialing active].include?(subscription.status) }
  end

  def generate_otp_secret
    self.update(
      otp_auth_secret: ROTP::Base32.random_base32,
      otp_recovery_secret: ROTP::Base32.random_base32,
      otp_persistence_seed: SecureRandom.hex
    )
  end

  def self.authenticate_mcp_token(raw_token)
    return nil if raw_token.blank?

    digest = digest_mcp_token(raw_token)
    user = find_by(mcp_token_digest: digest)
    return nil unless user&.mcp_available?
    return nil unless ActiveSupport::SecurityUtils.secure_compare(user.mcp_token_digest, digest)

    user
  end

  def self.digest_mcp_token(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end

  private

  def restrict_free_frequency
    if self.is_free? && self.frequency.present? && ENV['FREE_WEEK'] != 'true'
      self.update_columns(frequency: ["Sun"], previous_frequency: frequency)
    end
  end

  def send_welcome_email
    UserMailer.welcome_email(self).deliver_later
  rescue StandardError => e
    Sentry.set_user(id: self.id, email: self.email)
    Sentry.capture_exception(e, extra: { email_type: "Welcome Email" })
  end

  def notify_stripe
    return unless stripe_id.present?
    return unless (saved_changes[:email] || saved_changes[:first_name] || saved_changes[:last_name])

    params = {
      name: full_name,
      email: email
    }

    Stripe::Customer.update(stripe_id, params)
  end

  def disable_mcp_without_strong_auth
    return unless mcp_enabled?
    return if is_pro? && mcp_security_requirements_met?

    self.mcp_enabled = false
    self.mcp_token_digest = nil
    self.mcp_token_generated_at = nil
    self.mcp_last_used_at = nil
  end
end
