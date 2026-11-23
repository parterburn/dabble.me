# frozen_string_literal: true

Rails.application.config.to_prepare do
  DeviseOtp::Devise::OtpCredentialsController.prepend(OtpRefreshByEmailCode)
end
