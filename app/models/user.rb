class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  randomized_field :user_key, :length => 18, :prefix => 'u'

  has_many :entries, dependent: :destroy

  before_save { email.downcase! }

  serialize :frequency, Array

  scope :subscribed_to_emails, -> { where("frequency NOT LIKE '%[]%'") }
  scope :daily_emails, -> { where(:frequency => "---\n- Sun\n- Mon\n- Tue\n- Wed\n- Thu\n- Fri\n- Sat\n") }
  scope :with_entries, -> { includes(:entries).where("entries.id > 0").references(:entries) }
  scope :without_entries, -> { includes(:entries).where("entries.id IS null").references(:entries) }

  after_create do
    send_welcome_email
    subscribe_to_mailchimp if Rails.env.production?
  end

  def full_name
    "#{first_name} #{last_name}" if first_name.present? || last_name.present?
  end

  def full_name_or_email
    first_name.present? ? "#{first_name} #{last_name}" : email
  end

  def first_name_or_settings
    first_name.present? ? "#{first_name}" : "Settings"
  end

  def is_admin?
    email == ENV["ADMIN1"] || email == ENV["ADMIN2"]
  end
  
  def frequencies
    frequencies = ""
    self.frequency.each do |freq|
      if self.frequency.count == 1
        frequencies = "#{freq}"
      elsif self.frequency.count == 2
        if freq == self.frequency.last
          frequencies += " and #{freq}"
        else
          frequencies += "#{freq}"
        end
      else
        if freq == self.frequency.last
          frequencies += "and #{freq}"
        else
          frequencies += "#{freq}, "
        end
      end
    end
    frequencies
  end

  def random_entry(entry_date=nil)
    if entry_date.present?
      entry_date = Date.parse(entry_date.to_s)
      if exactly_last_year_entry = Entry.where(:user_id => id).where(:date => entry_date.last_year).first
        exactly_last_year_entry
      elsif exactly_30_days_ago = Entry.where(:user_id => id).where(:date => entry_date - 30.days).first
        exactly_30_days_ago
      elsif exactly_7_days_ago = Entry.where(:user_id => id).where(:date => entry_date - 7.days).first
        exactly_7_days_ago
      elsif (count = Entry.where(:user_id => id).where("date < (?)", entry_date - 365.days).count) > 0
        Entry.where(:user_id => id).where("date < (?)", entry_date - 365.days).offset(rand(count)).first #grab entry way back
      else
        self.random_entry
      end
    else
      if (count = Entry.where(:user_id => id).count) > 0
        Entry.where(:user_id => id).offset(rand(count)).first
      else
        nil
      end
    end
  end 

  def existing_entry(selected_date)
    begin
      selected_date = Date.parse(selected_date.to_s)
      Entry.where(:user_id => self.id, :date => selected_date).first
    rescue
      nil
    end
  end

  private

    def subscribe_to_mailchimp
      if ENV['MAILCHIMP_API_KEY'].present?
        gb = Gibbon::API.new
        gb.lists.subscribe({
          :id => ENV['MAILCHIMP_LIST_ID'],
          :email => {:email => self.email},
          :merge_vars => {
            :FNAME => self.first_name,
            :LNAME => self.last_name,
            :GROUP => "Signed Up" },
          :double_optin => false})
      end
    end

    def send_welcome_email
      UserMailer.welcome_email(self).deliver
    end

end