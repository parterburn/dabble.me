class User < ActiveRecord::Base
  VALID_EMAIL_REGEX = /\A[A-Z0-9._%'+-]+@[A-Z0-9.-]+\.[A-Z]{2,63}\z/i
  # Scanner infrastructure. Reject the domain and any subdomain on signup and email change.
  BLOCKED_EMAIL_DOMAINS = %w[pentest2bot.ink].freeze

  validates :email, format: { with: VALID_EMAIL_REGEX }, allow_blank: true
  validate :email_domain_not_blocked

  # Include default devise modules. Others available are:
  # :confirmable, :timeoutable and :omniauthable, :lockable
  devise :otp_authenticatable, :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable
  include SignedInDevices

  # user_key is the posting address (<user_key>@post.dabble.me) and appears in
  # every email we send. image_key names the user's S3 photo folder and never
  # changes once set. Existing users have image_key == user_key; new users get
  # two independent values so a photo URL never reveals the posting address.
  KEY_CHARACTERS = [*"0".."9", *"a".."z"].freeze

  # Plans an admin can pick on the payment form. Stripe subscriptions use the
  # "PayHere" names (see config/initializers/stripe.rb). Gumroad and PayPal
  # take no new subscribers, so the form offers their plans only to a user
  # who is already on one.
  SELECTABLE_PLANS = ["Free", "PRO Monthly PayHere", "PRO Yearly PayHere", "PRO Forever"].freeze

  # Signed token for the no-login settings and unsubscribe links in emails,
  # so those links don't carry the posting address. Its payload is readable,
  # so it holds a digest of user_key rather than the key: resetting the posting
  # address also retires old settings links.
  generates_token_for :email_settings do
    Digest::SHA256.hexdigest(user_key.to_s).first(16)
  end

  # Encrypted in the database. user_key and image_key are looked up by exact
  # value, so they use deterministic encryption; nothing can match them (or
  # the other columns) by substring in SQL.
  encrypts :user_key, :image_key, deterministic: true
  encrypts :first_name, :last_name, :past_filter, :otp_auth_secret, :otp_recovery_secret, :app_settings
  # Names are optional: a cleared field is stored as nil, never "".
  normalizes :first_name, :last_name, with: ->(name) { name.strip.presence }

  # Where the account was made (the signup_platform column). NULL for accounts from before it
  # was recorded. Set by whichever sign-up created the account: RegistrationsController (web)
  # and Api::V1::RegistrationsController (the app).
  SIGNUP_PLATFORMS = %w[web ios_app android_app].freeze
  APP_SIGNUP_PLATFORMS = %w[ios_app android_app].freeze
  validates :signup_platform, inclusion: { in: SIGNUP_PLATFORMS }, allow_nil: true

  validates :user_key, uniqueness: true
  validates :image_key, uniqueness: true, allow_nil: true
  before_create :assign_keys

  # "u" + 18 random characters, the format user_keys have always had. A value
  # already used in either column is never reused.
  def self.generate_unique_key
    loop do
      key = "u#{SecureRandom.alphanumeric(18, chars: KEY_CHARACTERS)}"
      return key unless where(user_key: key).or(where(image_key: key)).exists?
    end
  end

  has_many :entries, dependent: :destroy
  has_many :hashtags, dependent: :destroy
  has_many :exports, dependent: :destroy
  has_many :payments
  has_many :apple_subscriptions, dependent: :nullify
  has_one :gift_redemption, dependent: :delete
  has_many :webauthn_credentials, dependent: :destroy
  has_many :mcp_tool_invocations, dependent: :delete_all
  has_many :ignored_email_images, dependent: :delete_all
  has_many :ai_usages, dependent: :delete_all

  accepts_nested_attributes_for :hashtags, allow_destroy: true, :reject_if => proc { |att| att[:tag].blank? || att[:date].blank? }

  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :subscribed_to_emails, -> { not_deleted.where.not(frequency: []).where.not(frequency: nil) }
  scope :not_just_signed_up, -> { where("created_at < (?)", DateTime.now - 18.hours) }
  scope :daily_emails, -> { where(frequency: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]) }
  scope :with_entries, -> { includes(:entries).where("entries.id > 0").references(:entries) }
  scope :without_entries, -> { includes(:entries).where("entries.id IS null").references(:entries) }
  scope :free_only, -> { where("plan ILIKE '%free%' OR plan IS null") }
  scope :pro_only, -> { where("plan ILIKE '%pro%'") }
  # PRO that someone pays for: everything but a gifted year (Gift). Business metrics count these.
  scope :gifted, -> { where("plan ILIKE '%gift%'") }
  scope :paid_pro, -> { pro_only.where("plan NOT ILIKE '%gift%'") }
  scope :monthly, -> { where("plan ILIKE '%monthly%'") }
  scope :yearly, -> { where("plan ILIKE '%yearly%'") }
  scope :forever, -> { where("plan ILIKE '%forever%'") }
  scope :payhere_only, -> { where("plan ILIKE '%payhere%'") }
  scope :gumroad_only, -> { where("plan ILIKE '%gumroad%'") }
  scope :paypal_only, -> { where("plan ILIKE '%paypal%'") }
  scope :not_forever, -> { where("plan NOT ILIKE '%forever%'") }
  scope :apple_only, -> { where("plan ILIKE '%apple%'") }
  # App Store plans end when Apple says (AppStore::Entitlement), not by payment dates.
  scope :not_apple, -> { where("plan NOT ILIKE '%apple%'") }
  scope :referrals, -> { where("referrer IS NOT null") }

  # Users whose "first last" name holds every word of the query, ignoring case and order
  # ("ada", "lovelace ada"). Names are encrypted, so SQL can't search them: this decrypts
  # the names in Ruby and returns a relation of the matching ids.
  def self.with_name_matching(query)
    words = query.to_s.downcase.split
    return all if words.empty?

    ids = []
    where.not(first_name: nil).or(where.not(last_name: nil)).in_batches(of: 1000) do |batch|
      batch.pluck(:id, :first_name, :last_name).each do |id, first_name, last_name|
        name = "#{first_name} #{last_name}".downcase
        ids << id if words.all? { |word| name.include?(word) }
      end
    end
    where(id: ids)
  end

  after_commit :notify_stripe
  after_update :revoke_doorkeeper_oauth_if_downgraded_from_pro
  after_update :revoke_doorkeeper_oauth_if_credentials_changed
  before_update :unverify_changed_email, if: :will_save_change_to_email?

  EMAIL_DAYS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

  # The schedule can be changed from the no-login settings link, so keep it to
  # values the app knows: day abbreviations and real time zone names.
  before_validation { self.frequency = EMAIL_DAYS & Array(frequency) if will_save_change_to_frequency? }
  before_validation { self.send_timezone = send_timezone.gsub("&amp;", "&") if send_timezone.present? }
  validate :send_timezone_must_exist, if: :will_save_change_to_send_timezone?

  before_save { email&.gsub!(",",".")&.gsub!(".@", "@")&.downcase! }
  after_commit on: :update do
    restrict_free_frequency
  end
  # Back to Free some other way (a web plan ended, an admin's change) while an App Store
  # subscription is still paid for: that subscription makes it PRO again.
  after_commit :resume_apple_subscription, on: :update, if: -> { saved_change_to_plan? && is_free? }
  after_commit :send_welcome_email, on: :create

  def self.blocked_email_domain?(domain)
    normalized = domain.to_s.downcase.sub(/\.\z/, '')
    BLOCKED_EMAIL_DOMAINS.any? { |blocked| normalized == blocked || normalized.end_with?(".#{blocked}") }
  end

  # The iOS app's account-wide settings (Api::V1::AppSettingsController), kept as encrypted JSON.
  def app_settings_hash
    parsed = app_settings.present? ? JSON.parse(app_settings) : {}
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def app_settings_hash=(hash)
    self.app_settings = hash.presence&.to_json
  end

  def full_name
    [first_name, last_name].filter_map(&:presence).join(' ').presence
  end

  def abbreviated_name
    "#{first_name} #{last_name&.first&.upcase}".strip
  end

  def cleaned_to_address
    name = full_name.to_s.gsub(/[^\w\s-]/i, '').squish
    name.present? ? "#{name} <#{email}>" : email
  end

  def full_name_or_email
    first_name.present? ? full_name : email
  end

  def email_domain_not_blocked
    return if email.blank?

    domain = email.split('@', 2).last
    return unless self.class.blocked_email_domain?(domain)

    errors.add(:email, 'is not allowed')
  end

  def send_timezone_must_exist
    errors.add(:send_timezone, 'is not a known time zone') if ActiveSupport::TimeZone[send_timezone.to_s].nil?
  end

  # Gives the user a new posting address. Only the user (from the settings
  # page, after confirming) or an admin acting for them calls this; nothing
  # resets addresses automatically. Mail to the old address no longer matches
  # anyone, so EmailProcessor only accepts it from the account email with
  # SPF/DKIM passing. Photos stay put: they live under image_key, which never
  # changes. The image_key guard keeps that true even for a record missing one.
  def rotate_user_key!
    update!(image_key: image_key.presence || user_key, user_key: self.class.generate_unique_key)
  end

  def email_settings_token
    generate_token_for(:email_settings)
  end

  # p***@gmail.com, for pages shown without logging in.
  def masked_email
    email.to_s.sub(/\A(.)[^@]*(?=@)/, '\1***')
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
      elsif way_back_past_entries && (exact_years_back_entry = sample_entry(random_entries.where('extract(month from date) = ? AND extract(day from date) = ? AND extract(year from date) != ?', entry_date.month, entry_date.day, entry_date.year)))
        exact_years_back_entry
      elsif (exactly_last_year_entry = random_entries.where(date: entry_date.last_year).first)
        exactly_last_year_entry
      elsif (emails_sent % 3 == 0) && (exactly_30_days_ago = random_entries.where(date: entry_date.last_month).first)
        exactly_30_days_ago
      elsif random_entries.count < 50 && (emails_sent % 5 == 0) && (exactly_7_days_ago = random_entries.where(date: entry_date - 7.days).first)
        exactly_7_days_ago
      elsif way_back_past_entries && (emails_sent % 2 == 0) && random_entries.where('date < (?)', entry_date.last_year).count > 30
        sample_entry(random_entries.where('date < (?)', entry_date.last_year)) # grab entry way back
      else
        way_back_past_entries ? self.random_entry : sample_entry(random_entries.where("date > (?)", 1.year.ago))
      end
    else
      sample_entry(random_entries)
    end
  end

  # Entries.date is a datetime. Match any timestamp on the given calendar day
  # (UTC, matching config.time_zone) so non-midnight values still resolve.
  def existing_entry(selected_date)
    date = Date.parse(selected_date.to_s)
    entries.where(date: date.all_day).first
  rescue ArgumentError, TypeError
    nil
  end

  def can_ai?
    ai_opt_in?
  end

  # After an upgrade: puts back the email days a Free plan cut to Sunday, and
  # emails "Thanks for subscribing to Dabble Me PRO!". Used by the payment
  # form's "Send upgrade email" box and the button on the admin user page.
  def send_upgrade_email!
    update(frequency: previous_frequency) if Array(previous_frequency).any?
    UserMailer.thanks_for_paying(self).deliver_later
  end

  # OAuth MCP tokens and in-flight auth codes (Doorkeeper). Call when the user loses PRO access.
  # Pass keep_mobile_app: true when only MCP eligibility changed — the iOS app isn't gated on PRO.
  def revoke_doorkeeper_access_tokens!(keep_mobile_app: false)
    now = Time.current.utc
    tokens = Doorkeeper::AccessToken.where(resource_owner_id: id, revoked_at: nil)
    grants = Doorkeeper::AccessGrant.where(resource_owner_id: id, revoked_at: nil)
    if keep_mobile_app && (mobile_app_id = MobileApp.application_id)
      tokens = tokens.where.not(application_id: mobile_app_id)
      grants = grants.where.not(application_id: mobile_app_id)
    end
    tokens.update_all(revoked_at: now)
    grants.update_all(revoked_at: now)
  end

  # The first emailed-code sign-in to an unclaimed account (EmailSignIn.unclaimed?): whoever set
  # its password, passkeys, 2FA or sign-ins may not own the address, so all of them go. Clearing
  # the password changes the salt, which ends its web sessions and "Stay logged in" cookies.
  def clear_credentials_for_email_claim!
    transaction do
      webauthn_credentials.destroy_all
      disable_otp! if otp_enabled?
      revoke_doorkeeper_access_tokens!
      update_columns(encrypted_password: '', remember_created_at: nil, reset_password_token: nil,
                     reset_password_sent_at: nil)
      # Its old posting address may be known to whoever made the account: entries mailed there
      # would still land in this journal.
      rotate_user_key!
    end
  end

  # A new address hasn't been proven yet: its first code sign-in treats the account as unclaimed
  # (EmailSignIn.unclaimed?), so nobody can move an account onto someone else's address and
  # keep it once they sign in.
  def unverify_changed_email
    self.email_verified_at = nil
    self.email_changed_at = Time.current
  end

  def deletion_pending?
    deleted_at.present?
  end

  def cancel_pending_deletion!
    return false unless deletion_pending?

    update_column(:deleted_at, nil)
    true
  end

  def is_pro?
    plan_name == 'Dabble Me PRO'
  end

  # Signed up in one of the apps rather than on the web, so the welcome email leads with the app.
  def signed_up_in_app?
    APP_SIGNUP_PLATFORMS.include?(signup_platform)
  end

  def is_free?
    !is_pro?
  end

  # Set on an account made by entering an emailed code (EmailSignIn): it starts with no
  # password. One can be set later (Account Security, or Forgot password).
  attr_accessor :passwordless_signup

  # False for an account made by email code that hasn't set a password. Its sign-in is the
  # emailed code or a passkey, and an EmailCode stands in where the password is asked for.
  def has_password?
    encrypted_password.present?
  end

  # An account with no password never matches one, but it still spends a bcrypt hash on the
  # attempt, so a password sign-in takes as long as for any other address and its timing
  # doesn't show which addresses are email-code accounts.
  def self.no_password_digest
    @no_password_digest ||= Devise::Encryptor.digest(self, SecureRandom.hex(16))
  end

  def valid_password?(password)
    return super if has_password?

    Devise::Encryptor.compare(self.class, self.class.no_password_digest, password.to_s)
    false
  end

  # Devise ties sessions and "Stay logged in" cookies to the password hash's salt, so changing
  # the password signs other browsers out. An account with no password has no hash: it gets a
  # stand-in, which changes (signing those browsers out) once a password is set.
  def authenticatable_salt
    return super if has_password?

    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.key_generator.generate_key('passwordless_salt', 32),
                            "#{id}:#{created_at.to_i}").first(29)
  end

  # Set on a gift sign-up (Gift): the gift goes on just after the account is created, and the
  # welcome email's copy depends on the plan, so RegistrationsController sends it after that.
  attr_accessor :welcome_email_after_gift

  # On a gifted year of PRO (Gift), as opposed to a paid plan.
  def gifted_pro?
    is_pro? && plan.to_s.match?(/gift/i)
  end

  def gift_expires_at
    gift_redemption&.expires_at if gifted_pro?
  end

  # The gift's last day as the person sees it, e.g. "November 22, 2027".
  def gift_expires_on
    gift_expires_at&.in_time_zone(send_timezone.presence || "UTC")&.strftime("%B %-d, %Y")
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
    elsif plan && plan.match(/apple/i)
      'Apple'
    end
  end

  # The UUID the iOS app buys with (StoreKit's appAccountToken), made the first time it's asked
  # for. Apple puts it in the signed transaction, which is how a purchase names its account.
  # Two requests at once both get the one that was saved.
  def apple_account_token!
    return apple_account_token if apple_account_token.present?

    begin
      User.where(id: id, apple_account_token: nil).update_all(apple_account_token: SecureRandom.uuid)
    rescue ActiveRecord::RecordNotUnique
      retry
    end
    self.apple_account_token = User.where(id: id).pick(:apple_account_token)
    clear_attribute_change(:apple_account_token)
    apple_account_token
  end

  # A PRO plan's billing that deleting the account doesn't stop, so the person cancels it
  # themselves: Gumroad and PayPal bill on their own, and a Stripe plan with no customer on
  # file may have something left there (DeleteUserJob cancels the customer's subscriptions).
  # Nil when there's nothing (PRO Forever, say, or Stripe with a customer). The web's delete
  # page and the app's (Api::V1::AccountDeletionsController) both say so.
  def separate_billing_to_cancel
    # An App Store subscription keeps billing until it's cancelled in iOS Settings, whatever
    # the plan says (it may be a second subscription alongside a web one).
    if apple_subscriptions.any? { |s| s.entitles_pro? && s.auto_renew != false }
      return { provider: "Apple", certain: true }
    end

    provider = plan_type_unlinked
    return if provider == "Apple" # Cancelled already (auto-renew off), or over.
    return if !is_pro? || provider.blank?
    return if provider == "Stripe" && stripe_id.present?

    { provider: provider, certain: provider != "Stripe" }
  end

  def plan_type
    if plan && plan.match(/payhere/i)
      "<a href='/billing'>Stripe</a>"
    elsif plan && plan.match(/gumroad/i)
      "<a href='https://gumroad.com/login' target='_blank'>Gumroad</a>"
    elsif plan && plan.match(/paypal/i)
      'PayPal'
    elsif plan && plan.match(/apple/i)
      "<a href='https://apps.apple.com/account/subscriptions' target='_blank'>the App Store</a>"
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
      matcher = Entry::Matcher.any(filters.split(','))
      matcher ? matcher.ids(entries) : []
    end
  end

  # One entry of the relation at random. Picks among ids, so choosing from a
  # long journal doesn't load every entry.
  def sample_entry(relation)
    id = relation.unscope(:order).pluck(:id).sample
    id && entries.find_by(id: id)
  end

  def random_entries
    @random_entries ||= entries.where.not(id: past_filter_entry_ids)
  end

  # Signed in to the iOS app (a token of its that hasn't been revoked). Its push reminder and
  # widget look back on past entries too, whatever the email does.
  def uses_mobile_app?
    app_id = MobileApp.application_id
    app_id.present? && Doorkeeper::AccessToken.where(resource_owner_id: id, application_id: app_id, revoked_at: nil).exists?
  end

  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
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
    hashtags = entries.pluck(:body).flat_map { |body| Entry.hashtags_in(body) || [] }.map(&:downcase)
    if unique
      hashtags.group_by{|x| x}.sort_by{|k, v| -v.size}.map(&:first)
    else
      hashtags
    end
  end

  def send_time_in_mt
    send_time.hour + (ActiveSupport::TimeZone["America/Denver"].formatted_offset(false).to_i - ActiveSupport::TimeZone[send_timezone].formatted_offset(false).to_i)/100
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

  def disable_otp!
    clear_otp_fields!
    super
  end

  private

  def assign_keys
    self.user_key ||= self.class.generate_unique_key
    self.image_key ||= self.class.generate_unique_key
  end

  def restrict_free_frequency
    if self.is_free? && self.frequency.present?
      self.update_columns(frequency: ["Sun"], previous_frequency: frequency)
    end
  end

  def resume_apple_subscription
    AppStore::Entitlement.sync!(self) if apple_subscriptions.any?(&:entitles_pro?)
  end

  # Devise's validatable asks for a password on every new account; a passwordless sign-up has
  # none. Setting one later is validated as usual.
  def password_required?
    return false if passwordless_signup && password.nil? && password_confirmation.nil?

    super
  end

  def send_welcome_email
    return if welcome_email_after_gift

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

  def revoke_doorkeeper_oauth_if_downgraded_from_pro
    return unless saved_change_to_plan?

    previous_plan = plan_before_last_save.to_s
    current_plan = plan.to_s
    return unless previous_plan.match?(/pro/i)
    return if current_plan.match?(/pro/i)

    revoke_doorkeeper_access_tokens!(keep_mobile_app: true)
  end

  def revoke_doorkeeper_oauth_if_credentials_changed
    return unless saved_change_to_encrypted_password? ||
                  saved_change_to_email? ||
                  saved_change_to_otp_auth_secret? ||
                  (saved_change_to_otp_enabled? && !otp_enabled?)

    revoke_doorkeeper_access_tokens!
  end

  public

  OTP_MAX_CHALLENGE_FAILURES = 5
  OTP_MAX_USER_FAILURES = 10
  OTP_USER_LOCKOUT_WINDOW = 15.minutes

  def validate_otp_token(token, recovery = false)
    user_cache_key = "otp_user_failures:#{id}"
    if Rails.cache.read(user_cache_key).to_i >= OTP_MAX_USER_FAILURES
      update_columns(otp_session_challenge: nil, otp_challenge_expires: nil) if otp_session_challenge.present?
      return false
    end

    valid = super(token, recovery)
    challenge_cache_key = otp_session_challenge.present? ? "otp_challenge_failures:#{otp_session_challenge}" : nil

    if valid
      Rails.cache.delete(challenge_cache_key) if challenge_cache_key
      Rails.cache.delete(user_cache_key)
      if otp_session_challenge.present? || otp_challenge_expires.present?
        update_columns(otp_session_challenge: nil, otp_challenge_expires: nil)
      end
    else
      user_failures = Rails.cache.read(user_cache_key).to_i + 1
      Rails.cache.write(user_cache_key, user_failures, expires_in: OTP_USER_LOCKOUT_WINDOW)

      if challenge_cache_key
        failures = Rails.cache.read(challenge_cache_key).to_i + 1
        Rails.cache.write(challenge_cache_key, failures, expires_in: 5.minutes)
        if failures >= OTP_MAX_CHALLENGE_FAILURES || user_failures >= OTP_MAX_USER_FAILURES
          update_columns(otp_session_challenge: nil, otp_challenge_expires: nil)
        end
      end
    end
    valid
  end

  # The app's sign-in takes either kind of code in one field. The failure lockout covers both,
  # and a recovery code that works clears the failures the TOTP check just counted.
  def validate_otp_or_recovery_token(token)
    return false if otp_locked_out?
    return true if validate_otp_token(token)
    return false if otp_locked_out?
    return false unless validate_otp_recovery_token(token)

    Rails.cache.delete("otp_user_failures:#{id}")
    true
  end

  def otp_locked_out?
    Rails.cache.read("otp_user_failures:#{id}").to_i >= OTP_MAX_USER_FAILURES
  end

  def validate_otp_recovery_token(token)
    return false if token.blank?

    verified = recovery_otp.verify(token, otp_recovery_counter)
    if verified
      self.otp_recovery_counter += 1
      save!
    end
    verified
  end
  alias_method :valid_otp_recovery_token?, :validate_otp_recovery_token

end
