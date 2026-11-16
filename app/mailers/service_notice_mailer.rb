# The email of a ServiceNotice: a reminder to export your journal, under an
# optional message from the admin. The subject and everything below that
# message are fixed here, so the admin page can't be used to write anything else.
class ServiceNoticeMailer < ActionMailer::Base
  SUBJECT = "Export your Dabble Me journal"

  # Not "Paul // Dabble Me": whoever sends a notice may not be Paul.
  default from: "Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>"

  # `delivery` is the person's copy (ServiceNoticeDelivery). A preview has none.
  def export_reminder(user, message: nil, preview: false, delivery: nil)
    @user = user
    @message = message.to_s.strip.presence
    @export_url = export_entries_url
    if delivery
      @stop_url = notice_stop_url(token: delivery.stop_token)
      # One-click unsubscribe (RFC 8058), which mailbox providers expect on
      # mail sent to this many people: they POST to the URL themselves.
      headers["List-Unsubscribe"] = "<#{@stop_url}>"
      headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    end
    email = mail(to: user.cleaned_to_address, subject: preview ? "[Preview] #{SUBJECT}" : SUBJECT)
    email.mailgun_options = { tag: "Service notice" }
    email
  end
end
