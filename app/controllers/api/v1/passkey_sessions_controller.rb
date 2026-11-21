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
      skip_before_action :authorize_app_token!, :ensure_account_active

      CHALLENGE_LIFETIME = 5.minutes

      # GET /api/v1/session/passkey: the options for the app's assertion request.
      def new
        options = ::WebAuthn::Credential.options_for_get(user_verification: 'required')
        render json: {
          challenge_token: self.class.challenge_verifier.generate(options.challenge, expires_in: CHALLENGE_LIFETIME),
          challenge: options.challenge,
          rp_id: options.rp_id || WebAuthn.configuration.rp_id,
          timeout: options.timeout
        }
      end

      # POST /api/v1/session/passkey {challenge_token, credential: {id, rawId, type, response: {...}}}
      def create
        challenge = self.class.challenge_verifier.verified(params[:challenge_token].to_s)
        return auth_failed if challenge.blank? || !spend(challenge)

        webauthn_credential = ::WebAuthn::Credential.from_get(params.require(:credential))
        credential = WebauthnCredential.find_by(external_id: webauthn_credential.id)
        return auth_failed unless credential && owned_by_handle?(credential, webauthn_credential)

        # A passkey stands in for the password and the second factor, so the authenticator
        # must have verified the person (Face ID or the passcode).
        webauthn_credential.verify(challenge, public_key: credential.public_key,
                                              sign_count: credential.sign_count, user_verification: true)
        credential.update!(sign_count: webauthn_credential.sign_count)

        user = credential.user
        return auth_failed unless user.active_for_authentication?

        deletion_cancelled = user.cancel_pending_deletion!
        user.update_tracked_fields!(request)
        render json: MobileApp.token_response(MobileApp.issue_token!(user)).merge(deletion_cancelled: deletion_cancelled)
      rescue WebAuthn::Error, ArgumentError, ActionController::ParameterMissing
        auth_failed
      end

      def self.challenge_verifier
        Rails.application.message_verifier('api/v1/passkey_challenge')
      end

      private

      # False when this challenge was already used.
      def spend(challenge)
        Rails.cache.write("api/v1/passkey_challenge/#{Digest::SHA256.hexdigest(challenge)}", true,
                          unless_exist: true, expires_in: CHALLENGE_LIFETIME)
      end

      def auth_failed
        render_error(:unauthorized, 'passkey_failed', "That passkey didn't work. Try again, or use your password.")
      end

      # Discoverable credentials return the user handle set at registration (the user's id).
      def owned_by_handle?(credential, webauthn_credential)
        handle = webauthn_credential.raw_user_handle
        handle.present? && ActiveSupport::SecurityUtils.secure_compare(handle, credential.user_id.to_s)
      end
    end
  end
end
