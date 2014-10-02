class UserMailer < ActionMailer::Base
  default from: 'Dabble Me <pleasereply@dabble.me>'
 
  def welcome_email(user)
    @user = user
    mail(from: "Dabble Me <post+#{@user.user_key}@dabble.me>", to: @user.email, subject: "Let's write your first Dabble Me entry")
  end
end