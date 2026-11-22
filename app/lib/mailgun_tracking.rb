# frozen_string_literal: true

# Mailgun's click and open tracking, off for every email, newsletters included.
#
# Tracked links go through email.dabble.me and redirect, so a link in the daily email can't open
# the iOS app (a universal link has to be the address tapped), and a private journal has no
# business logging which links its writers follow or when they open their mail. An email that
# sets `mailgun_options[:tracking]` itself is left alone; none does today.
#
# Registered for every mailer, Devise's included (config/initializers/mailgun_tracking.rb).
class MailgunTracking
  OFF = { tracking: "no", "tracking-clicks": "no", "tracking-opens": "no" }.freeze

  def self.delivering_email(message)
    options = (message.mailgun_options || {}).symbolize_keys
    return if options.key?(:tracking)

    message.mailgun_options = options.merge(OFF)
  end
end
