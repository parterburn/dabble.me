# Sends one letter of a newsletter (see app/lib/newsletter.rb) to one person.
class NewsletterMailer < ActionMailer::Base
  default from: "Paul from Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>"

  def letter(user, newsletter_key, variant, preview: false)
    newsletter = Newsletter.find(newsletter_key)
    @rendered = newsletter.letter(variant).render(newsletter.values_for(user))
    @unsubscribe_url = email_updates_url(token: user.email_settings_token)
    @settings_url = settings_url(token: user.email_settings_token)
    @postal_address = ENV["MAILING_ADDRESS"]

    # One-click unsubscribe (RFC 8058), which mailbox providers expect on
    # bulk mail: they POST to the URL without showing the person a page.
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    subject = preview ? "[Preview: #{variant}] #{@rendered.subject}" : @rendered.subject
    email = mail(to: user.cleaned_to_address, subject: subject)
    email.mailgun_options = { tag: "Newsletter #{newsletter_key}" }
    email
  end
end
