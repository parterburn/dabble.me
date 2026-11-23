# frozen_string_literal: true

# Admin accounts keep their passkeys: nothing in the app, web or API, removes one, and the
# account can't be deleted there either (that would take its passkeys with it). Admin pages
# need a fresh passkey check (AdminAccess), so a passkey is what stands between the admin's
# inbox and the admin pages. Only the Rails console takes one away:
#
#   AdminAccounts.allow_passkey_removal { user.webauthn_credentials.find(ID).destroy! }
#
# Deleting an admin's account works the same way: AdminAccounts.allow_passkey_removal { user.destroy! }
#
# The console can also take an admin's password away, so they sign in with a passkey or an
# emailed code only (bin/rails "admin:remove_password[admin@example.com]").
module AdminAccounts
  PASSKEY_REMOVAL_KEY = :admin_accounts_passkey_removal

  class Refused < StandardError; end

  module_function

  def protected?(user)
    user.present? && user.admin?
  end

  # Lets the passkeys of admins be removed inside the block, on this thread only.
  def allow_passkey_removal
    previous = ActiveSupport::IsolatedExecutionState[PASSKEY_REMOVAL_KEY]
    ActiveSupport::IsolatedExecutionState[PASSKEY_REMOVAL_KEY] = true
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[PASSKEY_REMOVAL_KEY] = previous
  end

  def passkey_removal_allowed?
    ActiveSupport::IsolatedExecutionState[PASSKEY_REMOVAL_KEY] == true
  end

  # Clears an admin's password. Their sign-in is then a passkey, or an emailed code (plus their
  # 2FA code, if they have 2FA). Without the password hash the account's salt changes
  # (User#authenticatable_salt), so other browsers and "Stay logged in" cookies are signed
  # out. The app's sign-ins (OAuth tokens) stay.
  def remove_password!(user)
    raise Refused, "#{user.email} isn't an admin." unless protected?(user)
    raise Refused, "#{user.email} has no passkey. Add one before removing the password." unless user.webauthn_credentials.exists?
    raise Refused, "#{user.email} already has no password." unless user.has_password?

    user.update_columns(encrypted_password: '', reset_password_token: nil, reset_password_sent_at: nil,
                        remember_created_at: nil, updated_at: Time.current)
    user
  end
end
