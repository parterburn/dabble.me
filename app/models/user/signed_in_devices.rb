# The devices signed in to an account (UserSession) and signing them all out at once.
class User
  module SignedInDevices
    extend ActiveSupport::Concern

    included do
      has_many :user_sessions, dependent: :delete_all
      after_update :forget_signed_out_devices, if: :signed_in_devices_changed?
      # Prepended so it wraps any authenticatable_salt the class defines (passwordless accounts).
      prepend SaltWithSessionSalt
    end

    # Devise keeps the salt in each browser's session and in "Stay logged in" cookies, and turns
    # a browser away when it no longer matches. session_salt changes it without a new password.
    module SaltWithSessionSalt
      def authenticatable_salt
        salt = super
        return salt if session_salt.blank? || salt.blank?

        OpenSSL::HMAC.hexdigest('SHA256', session_salt, salt).first(29)
      end
    end

    # Sign out of all devices: every browser (sessions and "Stay logged in" cookies, including
    # ones from before sessions were listed), and the iOS app. Connected apps (Claude, ChatGPT)
    # keep their access: they're listed and removed on their own. Pass keep: to leave the
    # browser asking signed in; its controller then stores the new salt (bypass_sign_in).
    def sign_out_everywhere!(keep: nil)
      now = Time.current
      transaction do
        update_columns(session_salt: SecureRandom.hex(16), remember_created_at: nil, updated_at: now)
        if (app_id = MobileApp.application_id)
          Doorkeeper::AccessToken.where(resource_owner_id: id, application_id: app_id, revoked_at: nil)
                                 .update_all(revoked_at: now)
          Doorkeeper::AccessGrant.where(resource_owner_id: id, application_id: app_id, revoked_at: nil)
                                 .update_all(revoked_at: now)
        end
        sessions = user_sessions
        sessions = sessions.where.not(id: keep.id) if keep
        sessions.delete_all
      end
    end

    private

    # Same changes as revoke_doorkeeper_oauth_if_credentials_changed, which ends the app's tokens.
    def signed_in_devices_changed?
      saved_change_to_encrypted_password? || saved_change_to_email? || saved_change_to_otp_auth_secret? ||
        (saved_change_to_otp_enabled? && !otp_enabled?)
    end

    # Those changes revoke the app's tokens, so its rows go. A new password also ends other
    # browsers (Devise's salt changes); the one making the change stays.
    def forget_signed_out_devices
      user_sessions.ios_app.delete_all
      return unless saved_change_to_encrypted_password?

      current = Current.user_session
      others = user_sessions.web
      others = others.where.not(id: current.id) if current&.user_id == id
      others.delete_all
    end
  end
end
