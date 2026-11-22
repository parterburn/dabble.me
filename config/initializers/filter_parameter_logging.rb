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
  # Passkey setup from the app: setup_token stands in for the password for a few minutes.
  :setup_token,
  :passkey_setup_token,
  :challenge_token,
  :body,
  :raw_body,
  :html,
  :stripped_html,
  :original_email_body,
  :original_email,
  :text_body,
  :entry_template,
  :gift_code, # a gift link's code (Gift) works for anyone who has it
  :first_name,
  :last_name,
  # Apple-signed transactions and notifications (they carry the account's appAccountToken).
  :signed_transaction,
  :signedPayload,
  :signedTransactionInfo,
  :signedRenewalInfo,
  /\Aentry\z/i
]
