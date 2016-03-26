class UserMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)

  default from: "Dabble Me Support <hello@#{ENV['MAIN_DOMAIN']}>"

  def welcome_email(user)
    @user = user
    @user.increment!(:emails_sent)
    headers['X-Mailgun-Tag'] = 'Welcome'
    mail(from: "Dabble Me <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: user.email, subject: "Let's write your first Dabble Me entry")
  end

  def second_welcome_email(user)
    @user = user
    @user.increment!(:emails_sent)
    @first_entry = user.entries.first
    if @first_entry.present?
      @first_entry_image_url = @first_entry.image.url || @first_entry.filepicker_url
    end    
    headers['X-Mailgun-Tag'] = 'Welcome'
    mail(from: "Dabble Me <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: user.email, subject: 'Congrats on writing your first entry!')
  end

  def thanks_for_paying(user)
    @user = user
    @user.increment!(:emails_sent)
    headers['X-Mailgun-Tag'] = 'Thanks'
    mail(to: user.email, subject: 'Thanks for subscribing to Dabble Me PRO!')
  end

  def downgraded(user)
    @user = user
    @user.increment!(:emails_sent)
    headers['X-Mailgun-Tag'] = 'Downgraded'
    mail(to: user.email, subject: '[ACTION REQUIRED] Account Downgraded')
  end

  def no_user_here(email, source)
    mail(to: "hello@#{ENV['MAIN_DOMAIN']}", subject: '[REFUND REQUIRED] Payment Without a User', body: "#{email} does not exist as a user at #{ENV['MAIN_DOMAIN']}. Payment via #{source}.")
  end
end
