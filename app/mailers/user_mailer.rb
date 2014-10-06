class UserMailer < ActionMailer::Base
  default from: 'Dabble Me <hello@dabble.me>'
 
  def welcome_email(user)
    @user = user
    mail(from: "Dabble Me <post+#{@user.user_key}@dabble.me>", to: @user.email, subject: "Let's write your first Dabble Me entry")
  end

 def second_welcome_email(user)
    @user = user
    mail(from: "Dabble Me <post+#{@user.user_key}@dabble.me>", to: @user.email, subject: "Congrats on writing your first entry!")
  end
end