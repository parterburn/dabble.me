class UserMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)
  helper ApplicationHelper
  helper EntriesHelper
  helper :application

  default from: "Paul from Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>"

  def welcome_email(user)
    @user = user
    @user.increment!(:emails_sent)
    @user.update_columns(last_sent_at: Time.now)
    email = mail(from: "Dabble me. <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: user.cleaned_to_address, subject: "Let's write your first Dabble Me entry")
    email.mailgun_options = {tag: 'Welcome'}
  end

  def second_welcome_email(user)
    @user = user
    @user.increment!(:emails_sent)
    @first_entry = user.entries.first
    if @first_entry.present?
      @first_entry_image_url = @first_entry.image_url_cdn
    end
    email = mail(from: "Dabble me. <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: user.cleaned_to_address, subject: 'Congrats on writing your first entry!')
    email.mailgun_options = {tag: 'Welcome'}
  end

  def thanks_for_paying(user)
    @user = user
    @user.increment!(:emails_sent)
    email = mail(from: "Dabble me. <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: user.cleaned_to_address, subject: 'Thanks for subscribing to Dabble Me PRO!')
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

  def export_ready(user, file, filename, format)
    @user = user
    @filename = filename
    content_type = format.to_s == 'json' ? 'application/json' : 'text/plain'
    attachments[filename] = { mime_type: content_type, content: file.read }
    email = mail(to: user.email, subject: 'Your Dabble Me export is ready')
    email.mailgun_options = { tag: 'Export' }
  end

  # Sent after the user resets their posting address. It comes from the new
  # address, so they can save it to their contacts straight from this email.
  def posting_address_changed(user)
    @user = user
    @user.increment!(:emails_sent)
    email = mail(from: "Dabble me. <#{user.user_key}@#{ENV['SMTP_DOMAIN']}>", to: user.cleaned_to_address, subject: "Your new Dabble Me posting address")
    email.mailgun_options = { tag: "Security" }
  end

  def passkey_added(user, nickname)
    @user = user
    @nickname = nickname
    @user.increment!(:emails_sent)
    email = mail(to: user.cleaned_to_address, subject: "Passkey added to your Dabble Me account")
    email.mailgun_options = { tag: "Security" }
  end

  # Sent when someone taps "Delete Account" in the iOS app. Deletion itself still happens on
  # the web (signed in + current password, then a 1-hour grace period), so this adds a step
  # that proves mailbox access and can't be completed by an accidental tap.
  def account_deletion_requested(user)
    @user = user
    @user.increment!(:emails_sent)
    email = mail(to: user.cleaned_to_address, subject: "Finish deleting your Dabble Me account")
    email.mailgun_options = { tag: "Security" }
  end

end
