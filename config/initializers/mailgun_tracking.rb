# frozen_string_literal: true

# Click and open tracking is off for every email; a mailer could opt in (see MailgunTracking), but none does.
# Registered once the app's classes can be loaded; harmless to run again after a reload, since
# the interceptor leaves a message it has already marked alone.
Rails.application.config.to_prepare do
  ActionMailer::Base.register_interceptor(MailgunTracking)
end
