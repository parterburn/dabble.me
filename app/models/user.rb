class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  has_many :entries, dependent: :destroy

  serialize :frequency, Array

  def full_name_or_email
    first_name.present? ? "#{first_name} #{last_name}" : email
  end
  
end