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

  def export_ready(user, file, filename, format)
    @user = user
    @filename = filename
    content_type = format.to_s == 'json' ? 'application/json' : 'text/plain'
    attachments[filename] = { mime_type: content_type, content: file.read }
    email = mail(to: user.email, subject: 'Your Dabble Me export is ready')
    email.mailgun_options = { tag: 'Export' }
  end

  def x_bookmarks_summary(user)
    @user = user
    @bookmarks = user.x_bookmarks.where(created_at: DateTime.now.beginning_of_month..DateTime.now.end_of_month)
    return unless @bookmarks.any?

    @summary = AiBookmarkSummarizer.new.summarize!(bookmarks: @bookmarks)
    email = mail(
      from: "X Bookmarks <no-reply@#{ENV['SMTP_DOMAIN']}>",
      to: user.cleaned_to_address,
      subject: "#{@bookmarks.count} #{'bookmark'.pluralize(@bookmarks.count)} this month"
    )
    email.mailgun_options = { tag: 'XBookmarksSummary' }
  end
end
