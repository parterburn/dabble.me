class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :timeoutable and :omniauthable, :lockable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable, :paranoid_verification

  randomized_field :user_key, length: 18, prefix: 'u'

  has_many :entries, dependent: :destroy
  has_many :hashtags, dependent: :destroy
  has_many :payments
  has_many :reviews

  accepts_nested_attributes_for :hashtags, allow_destroy: true, :reject_if => proc { |att| att[:tag].blank? || att[:date].blank? }

  serialize :frequency, Array

  scope :subscribed_to_emails, -> { where("frequency NOT LIKE '%[]%'") }
  scope :not_just_signed_up, -> { where("created_at < (?)", DateTime.now - 18.hours) }
  scope :daily_emails, -> { where(frequency: "---\n- Sun\n- Mon\n- Tue\n- Wed\n- Thu\n- Fri\n- Sat\n") }
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

  before_save { email.downcase! }
  after_commit on: :update do
    restrict_free_frequency
    subscribe_to_mailchimp
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

      if (exact_last_leap_year_entry = random_entries.where('extract(month from date) = ? AND extract(day from date) = ? AND extract(year from date) = ?', 2, 29, entry_date.last_year.year).first).present?
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

  def is_admin?
    admin_emails.include?(self.email)
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

  def plan_frequency
    if plan && plan.match(/monthly/i)
      'Monthly'
    elsif plan && plan.match(/yearly/i)
      'Yearly'
    end
  end

  def plan_type_unlinked
    if plan && plan.match(/payhere/i)
      "PayHere"
    elsif plan && plan.match(/gumroad/i)
      "Gumroad"
    elsif plan && plan.match(/paypal/i)
      'PayPal'
    end
  end

  def plan_type
    if plan && plan.match(/payhere/i)
      "<a href='https://app.payhere.co/customers' target='_blank'>PayHere</a>"
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
    if last_post = self.entries.where("date < ?", Time.now).first
      ActionController::Base.helpers.number_with_delimiter((Time.now.to_date - last_post.date.to_date).to_i)
    else
      ''
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

  def after_database_authentication
    if self.is_admin? && self.generate_paranoid_code
      UserMailer.confirm_user(self).deliver_later
    elsif self.need_paranoid_verification?
      UserMailer.confirm_user(self).deliver_later
    end
  rescue
    if Rails.env.development?
      p "PARANOID CODE: #{self.paranoid_verification_code}"
    end
  end

  def remember_me
    super.present? ? super : true
  end

  alias_method :original_hashtags, :hashtags
  def hashtags
    @hashtags ||= begin
      used_hashtags(entries, true).first(5).each do |h|
        next if h.downcase.in?(original_hashtags.pluck(:tag)&.map(&:downcase))
        original_hashtags.build(tag: h)
      end
      original_hashtags.build      
      original_hashtags.to_a
    end
  end

  def hashtags_attributes=(value)
    (0..value.count-1).each do |i|
      record = value[i.to_s]
      if record["tag"].present?
        t = original_hashtags.where('lower(tag) = ?', record["tag"].downcase).first
        if t.present?
          if record["date"].blank?
            h.destroy
          else
            t.update(date: Date.parse(record["date"]))
          end
        elsif record["date"].present?
          original_hashtags.create(tag: record["tag"], date: Date.parse(record["date"]))
        end
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

  def karma
    reviews.where('status <> "new"').count
  end

  private

  def restrict_free_frequency
    if self.is_free? && self.frequency.present? && ENV['FREE_WEEK'] != 'true'
      self.update_column(:frequency, [self.frequency.first])
    end
  end

  def subscribe_to_mailchimp
    email_lookup = self.previous_changes["email"]&.last(2)&.first&.downcase
    UserJob.perform_later(email_lookup, self.id)
  end

  def send_welcome_email
    UserMailer.welcome_email(self).deliver_later
  rescue StandardError => e
    Rails.logger.warn("Error sending welcome email to #{self.email}: #{e}")
  end

  def admin_emails
    ENV.fetch('ADMIN_EMAILS').split(',')
  end
end
