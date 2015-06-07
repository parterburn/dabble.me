class UserMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)
  include FilepickerRails::ApplicationHelper
    
  default from: "Dabble Me Support <hello@#{ENV['MAIN_DOMAIN']}>"
 
  def welcome_email(user)
    @user = user
    headers['x-smtpapi'] = { :category => [ "DB_Welcome" ] }.to_json
    mail(from: "Dabble Me <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: user.email, subject: "Let's write your first Dabble Me entry")
  end

 def second_welcome_email(user)
    @user = user
    @first_entry = user.entries.first
    @first_entry_filepicker_url = filepicker_image_url(@first_entry.image_url, w: 300, h: 300, fit: 'max', cache: true, rotate: :exif) if @first_entry.present? && @first_entry.image_url.present?
    headers['x-smtpapi'] = { :category => [ "DB_Welcome" ] }.to_json
    mail(from: "Dabble Me <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: user.email, subject: "Congrats on writing your first entry!")
  end

 def thanks_for_paying(user)
    @user = user
    headers['x-smtpapi'] = { :category => [ "DB_Thanks" ] }.to_json
    mail(to: user.email, subject: "Thanks for subscribing to Dabble Me PRO!")
  end  
end