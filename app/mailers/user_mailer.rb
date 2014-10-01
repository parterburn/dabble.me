class UserMailer < ActionMailer::Base
  default from: 'Dabble Me <pleasereply@dabble.me>'
 
  def welcome_email(user)
    @user = user
    mail(from: "Dabble Me <post+#{Time.now.in_time_zone(user.send_timezone).strftime("%Y-%m-%d")}+#{@user.user_key}@email.dabble.me>", to: @user.email, subject: "Welcome to Dabble Me")
  end
end