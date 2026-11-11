# Sends one letter of a newsletter (see app/lib/newsletter.rb) to one person.
class NewsletterMailer < ActionMailer::Base
  default from: "Paul // Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>"

  def letter(user, newsletter_key, variant, preview: false)
    newsletter = Newsletter.find(newsletter_key)
    @rendered = newsletter.letter.render(newsletter.values_for(user), variant: variant)
    @pro = user.is_pro?
    @unsubscribe_url = email_updates_url(token: user.email_settings_token)
    @settings_url = settings_url(token: user.email_settings_token)
    @postal_address = ENV["MAILING_ADDRESS"]

    # One-click unsubscribe (RFC 8058), which mailbox providers expect on
    # bulk mail: they POST to the URL without showing the person a page.
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    subject = preview ? "[Preview: #{variant}] #{@rendered.subject}" : @rendered.subject
    email = mail({ to: user.cleaned_to_address, subject: subject }.merge(sender_options(newsletter, variant)))
    email.mailgun_options = { tag: "Newsletter #{newsletter_key}" }
    email
  end

  private

  # A plan can send from its own address and Mailgun domain, so its mail
  # builds a reputation apart from the journal emails.
  def sender_options(newsletter, variant)
    sender = newsletter.sender_for(newsletter.plan_of_variant(variant))
    options = { from: sender.from, reply_to: sender.reply_to }.compact
    options[:delivery_method_options] = { domain: sender.mailgun_domain } if sender.mailgun_domain
    options
  end
end
