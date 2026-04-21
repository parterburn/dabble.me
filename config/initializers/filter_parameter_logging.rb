# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :password,
  :current_password,
  :password_confirmation,
  :access_token,
  :mcp_token,
  :authorization,
  :otp_attempt,
  :otp_code,
  :raindrop_api_key,
  :x_access_token,
  :x_refresh_token
]
