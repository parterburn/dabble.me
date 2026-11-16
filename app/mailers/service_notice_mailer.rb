# The email of a ServiceNotice: a reminder to export your journal, under an
# optional message from the admin. The subject and everything below that
# message are fixed here, so the admin page can't be used to write anything else.
class ServiceNoticeMailer < ActionMailer::Base
  SUBJECT = "Export your Dabble Me journal"

  # Not "Paul // Dabble Me": whoever sends a notice may not be Paul.
  default from: "Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>"

  def export_reminder(user, message: nil, preview: false)
    @user = user
    @message = message.to_s.strip.presence
    @export_url = export_entries_url
    email = mail(to: user.cleaned_to_address, subject: preview ? "[Preview] #{SUBJECT}" : SUBJECT)
    email.mailgun_options = { tag: "Service notice" }
    email
  end
end
