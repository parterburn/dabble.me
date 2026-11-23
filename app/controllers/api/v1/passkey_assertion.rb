# frozen_string_literal: true

require 'webauthn'

module Api
  module V1
    # Checks a passkey assertion from the app against a challenge handed out by
    # GET /api/v1/session/passkey: the same ceremony as the web's Passkeys::SessionsController.
    # Signing in uses it (PasskeySessionsController), and so does confirming Delete Account
    # (AccountDeletionsController) for someone who signs in with a passkey alone.
    module PasskeyAssertion
      CHALLENGE_LIFETIME = 5.minutes

      private

      # The passkey's owner, or nil when the challenge or the assertion doesn't hold up. Reads
      # params[:challenge_token] and params[:credential] (WebAuthn's JSON).
      def passkey_user
        challenge = PasskeySessionsController.challenge_verifier.verified(params[:challenge_token].to_s)
        return if challenge.blank? || !spend_passkey_challenge(challenge)

        webauthn_credential = ::WebAuthn::Credential.from_get(params.require(:credential))
        credential = WebauthnCredential.find_by(external_id: webauthn_credential.id)
        return unless credential && owned_by_handle?(credential, webauthn_credential)

        # A passkey stands in for the password and the second factor, so the authenticator
        # must have verified the person (Face ID or the passcode).
        webauthn_credential.verify(challenge, public_key: credential.public_key,
                                              sign_count: credential.sign_count, user_verification: true)
        credential.update!(sign_count: webauthn_credential.sign_count)
        credential.user
      rescue WebAuthn::Error, ArgumentError, ActionController::ParameterMissing
        nil
      end

      # False when this challenge was already used.
      def spend_passkey_challenge(challenge)
        Rails.cache.write("api/v1/passkey_challenge/#{Digest::SHA256.hexdigest(challenge)}", true,
                          unless_exist: true, expires_in: CHALLENGE_LIFETIME)
      end

      # Discoverable credentials return the user handle set at registration (the user's id).
      def owned_by_handle?(credential, webauthn_credential)
        handle = webauthn_credential.raw_user_handle
        handle.present? && ActiveSupport::SecurityUtils.secure_compare(handle, credential.user_id.to_s)
      end
    end
  end
end
