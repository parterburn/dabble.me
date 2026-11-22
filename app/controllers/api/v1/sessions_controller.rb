# frozen_string_literal: true

module Api
  module V1
    # Native sign-in for the iOS app: email and password, then the 2FA code when the account
    # has one. Answers with tokens the way /oauth/token does (MobileApp.token_response).
    # Rack::Attack throttles it like the web's /users/sign_in.
    class SessionsController < BaseController
      skip_before_action :authorize_app_token!, :ensure_account_active

      # POST /api/v1/session {email, password, otp_code?}
      def create
        user = User.find_for_authentication(email: params[:email].to_s.strip.downcase)
        # Same answer for an unknown email as for a wrong password (Devise's paranoid mode),
        # in about the same time: hash the password anyway when there's no account.
        User.new(password: params[:password].to_s) unless user
        unless user&.valid_password?(params[:password].to_s) && user.active_for_authentication?
          return render_error(:unauthorized, 'invalid_credentials', 'Incorrect email or password.')
        end

        if user.otp_enabled?
          code = params[:otp_code].to_s.gsub(/\s/, '')
          if code.blank?
            return render_error(:unauthorized, 'otp_required', 'Enter the 6-digit code from your authenticator app.')
          end
          unless user.validate_otp_or_recovery_token(code)
            return render_error(:unauthorized, 'invalid_otp', "That code didn't work. Try the newest one, or a recovery code.")
          end
        end

        # Signing back in keeps an account that was set to be deleted, as on the web.
        deletion_cancelled = user.cancel_pending_deletion!
        user.update_tracked_fields!(request)
        token = MobileApp.issue_token!(user)
        render json: MobileApp.token_response(token)
                               .merge(deletion_cancelled: deletion_cancelled, **MobileApp.passkey_setup(user, token))
      end
    end
  end
end
