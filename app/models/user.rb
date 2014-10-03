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
  
  def random_entry
    if (count = Entry.where(:user_id => id).count) > 0
      Entry.where(:user_id => id).offset(rand(count)).first
    else
      nil
    end
  end

  def existing_entry(date)
    begin
      selected_date = Date.parse(date)
      Entry.where(:user_id => self.id, :date => selected_date.beginning_of_day..selected_date.end_of_day).first
    rescue
      nil
    end
  end  

  private

    def subscribe_to_mailchimp
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

    def send_welcome_email
      UserMailer.welcome_email(self).deliver
    end

end