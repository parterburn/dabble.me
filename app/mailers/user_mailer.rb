class UserMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)
  helper ApplicationHelper
  helper EntriesHelper
  helper :application

  default from: "Paul // Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>"

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

  # A payment notification that wasn't recorded. PaymentsController passes the
  # provider, why it was refused, and the account it matched, if any.
  def no_user_here(params, provider: nil, reason: nil, user_id: nil)
    @params = params.to_h
    @provider = provider
    @reason = reason
    @user = User.find_by(id: user_id) if user_id
    mail(to: "hello@#{ENV['MAIN_DOMAIN']}", subject: '[REFUND REQUIRED] Payment Without a User')
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

  # The link opens the app, which asks for a sign-in before the download.
  def export_ready(export)
    @export = export
    @user = export.user
    @export_url = export_url(export)
    email = mail(to: @user.email, subject: 'Your Dabble Me export is ready')
    email.mailgun_options = { tag: 'Export' }
  end

  def export_failed(export)
    @user = export.user
    @settings_url = edit_user_registration_url(anchor: 'export')
    email = mail(to: @user.email, subject: "We couldn't finish your Dabble Me export")
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

  # Sent when the user approves a new third-party OAuth app (Claude, ChatGPT, other MCP
  # clients), so a consent-phishing approval doesn't go unnoticed.
  def oauth_app_connected(user, app_name, redirect_host: nil, verified: false)
    @user = user
    @app_name = app_name
    @redirect_host = redirect_host
    @verified = verified
    @user.increment!(:emails_sent)
    email = mail(to: user.cleaned_to_address, subject: "New app connected to your Dabble Me account")
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
