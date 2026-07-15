# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
# Journal body fields are private content — keep them out of logs and Sentry extras.
Rails.application.config.filter_parameters += [
  :password,
  :current_password,
  :password_confirmation,
  :access_token,
  :authorization,
  :otp_attempt,
  :otp_code,
  :body,
  :raw_body,
  :html,
  :stripped_html,
  :original_email_body,
  :original_email,
  :text_body
]
