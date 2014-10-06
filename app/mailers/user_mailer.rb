class UserMailer < ActionMailer::Base
  default from: "Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>"
 
  def welcome_email(user)
    @user = user
    mail(from: "Dabble Me <#{@user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: @user.email, subject: "Let's write your first Dabble Me entry")
  end

 def second_welcome_email(user)
    @user = user
    mail(from: "Dabble Me <#{@user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: @user.email, subject: "Congrats on writing your first entry!")
  end
end