# frozen_string_literal: true

# devise-otp asks for the password again before the two-factor settings page
# (otp_credentials_refresh, 15 minutes after the 2FA sign-in). An account with no password
# (an email-code sign-up, or an admin whose password was removed: AdminAccounts) could never
# get past that, so it confirms with a code emailed to it instead, as Account Security does.
module OtpRefreshByEmailCode
  def set_refresh
    ensure_resource!
    return super if resource.has_password?

    if EmailCode.confirm(resource, params.dig(resource_name, :email_code))
      done_valid_refresh
    else
      failed_refresh
    end
  end
end
