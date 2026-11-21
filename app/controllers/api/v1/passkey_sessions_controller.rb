# frozen_string_literal: true

require 'webauthn'

module Api
  module V1
    # Native passkey sign-in for the iOS app (ASAuthorizationPlatformPublicKeyCredentialProvider).
    # The same ceremony as the web's Passkeys::SessionsController, with the same passkeys: the
    # app is allowed to use dabble.me's (relying party "dabble.me") through the webcredentials
    # entry in /.well-known/apple-app-site-association. There's no session cookie, so the
    # challenge travels as a signed, short-lived token and is spent once (Rails.cache).
    class PasskeySessionsController < BaseController
      include PasskeyAssertion

      skip_before_action :authorize_app_token!, :ensure_account_active

      # GET /api/v1/session/passkey: the options for the app's assertion request.
      def new
        options = ::WebAuthn::Credential.options_for_get(user_verification: 'required')
        render json: {
          challenge_token: self.class.challenge_verifier.generate(options.challenge, expires_in: PasskeyAssertion::CHALLENGE_LIFETIME),
          challenge: options.challenge,
          rp_id: options.rp_id || WebAuthn.configuration.rp_id,
          timeout: options.timeout
        }
      end

      # POST /api/v1/session/passkey {challenge_token, credential: {id, rawId, type, response: {...}}}
      def create
        user = passkey_user
        return auth_failed unless user&.active_for_authentication?

        deletion_cancelled = user.cancel_pending_deletion!
        user.update_tracked_fields!(request)
        render json: MobileApp.token_response(MobileApp.issue_token!(user)).merge(deletion_cancelled: deletion_cancelled)
      end

      def self.challenge_verifier
        Rails.application.message_verifier('api/v1/passkey_challenge')
      end

      private

      def auth_failed
        render_error(:unauthorized, 'passkey_failed', "That passkey didn't work. Try again, or use your password.")
      end
    end
  end
end
