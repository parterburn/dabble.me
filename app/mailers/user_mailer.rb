class UserMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)
  helper ApplicationHelper
  helper EntriesHelper
  helper :application

  default from: "Dabble Me Support <hello@#{ENV['MAIN_DOMAIN']}>"

  def welcome_email(user)
    @user = user
    @user.increment!(:emails_sent)
    @user.update_columns(last_sent_at: Time.now)
    email = mail(from: "Dabble Me ✏ <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: user.cleaned_to_address, subject: "Let's write your first Dabble Me entry")
    email.mailgun_options = {tag: 'Welcome'}
  end

  def second_welcome_email(user)
    @user = user
    @user.increment!(:emails_sent)
    @first_entry = user.entries.first
    if @first_entry.present?
      @first_entry_image_url = @first_entry.image_url_cdn
    end
    email = mail(from: "Dabble Me ✏ <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: user.cleaned_to_address, subject: 'Congrats on writing your first entry!')
    email.mailgun_options = {tag: 'Welcome'}
  end

  def thanks_for_paying(user)
    @user = user
    @user.increment!(:emails_sent)
    email = mail(to: user.cleaned_to_address, subject: 'Thanks for subscribing to Dabble Me PRO!')
    email.mailgun_options = {tag: 'Thanks'}
  end

  def downgraded(user)
    @user = user
    @user.increment!(:emails_sent)
    email = mail(to: user.cleaned_to_address, subject: '[ACTION REQUIRED] Account Downgraded')
    email.mailgun_options = {tag: 'Downgraded'}
  end

  def no_user_here(params)
    mail(to: "hello@#{ENV['MAIN_DOMAIN']}", subject: '[REFUND REQUIRED] Payment Without a User', body: params.to_yaml)
  end

  def failed_entry(user, errors, date, body)
    @user = user
    @errors = errors
    @date = date
    @body = body
    # email = mail(to: user.cleaned_to_address, subject: 'Error saving entry for #{date}')
    email = mail(to: "hello@#{ENV['MAIN_DOMAIN']}", subject: "Error saving entry for user #{user.id}")
    email.mailgun_options = {tag: 'EntryError'}
  end

  # def referred_users(id, email)
  #   @ref_id = id
  #   if id == '*'
  #     @users = User.referrals.where('created_at > ?', 1.week.ago)
  #   else
  #     @users = User.referrals.where(referrer: id).where('created_at > ?', 1.week.ago)
  #   end
  #   return unless @users.present?

  #   email = mail(to: email, subject: 'Dabble Me Referrals')
  #   email.mailgun_options = {tag: 'Referrals'}
  # end
end
