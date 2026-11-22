# frozen_string_literal: true

require 'webauthn'

module Api
  module V1
    # Adding a passkey from the app (ASAuthorizationPlatformPublicKeyCredentialProvider's
    # registration request): the same passkey the web's Passkeys::RegistrationsController makes,
    # for relying party dabble.me, so it signs in on both. The app offers it right after a
    # password sign-in or sign-up, and from Settings while the account has none.
    #
    # As on the web, adding one needs the password, except within SETUP_WINDOW of signing in
    # with it in the app: the sign-in answer carries a passkey_setup_token
    # (SessionsController, RegistrationsController) that stands in for typing it again.
    class PasskeysController < BaseController
      SETUP_WINDOW = 15.minutes

      # GET /api/v1/passkeys/new: what the app's registration request needs.
      def new
        existing = current_user.webauthn_credentials.pluck(:external_id)
        # The user handle is the account's id, as the web's passkeys have it (and sign-in checks).
        user_handle = Base64.urlsafe_encode64(current_user.id.to_s, padding: false)
        options = ::WebAuthn::Credential.options_for_create(
          user: { id: user_handle, name: current_user.email, display_name: current_user.full_name_or_email },
          exclude_credentials: existing,
          authenticator_selection: { resident_key: 'required', user_verification: 'required' }
        )
        render json: {
          challenge_token: self.class.challenge_verifier.generate(
            { 'challenge' => options.challenge, 'user_id' => current_user.id },
            expires_in: PasskeyAssertion::CHALLENGE_LIFETIME
          ),
          challenge: options.challenge,
          rp_id: WebAuthn.configuration.rp_id,
          user_id: user_handle,
          user_name: current_user.email,
          exclude_credentials: existing
        }
      end

      # POST /api/v1/passkeys {challenge_token, credential (WebAuthn's JSON), setup_token | current_password}
      def create
        unless setup_token_valid? || current_user.valid_password?(params[:current_password].to_s)
          return render_error(:forbidden, 'incorrect_password', 'Incorrect password.')
        end

        payload = self.class.challenge_verifier.verified(params[:challenge_token].to_s)
        challenge = payload.is_a?(Hash) && payload['user_id'] == current_user.id ? payload['challenge'] : nil
        return failed if challenge.blank? || !spend_challenge(challenge)

        created = ::WebAuthn::Credential.from_create(params.require(:credential))
        created.verify(challenge, user_verification: true)
        credential = current_user.webauthn_credentials.build(
          external_id: created.id,
          public_key: created.public_key,
          nickname: params[:nickname].to_s.strip.first(60).presence || "iPhone passkey #{current_user.webauthn_credentials.count + 1}",
          sign_count: created.sign_count
        )
        return failed(credential.errors.full_messages) unless credential.save

        UserMailer.passkey_added(current_user, credential.nickname).deliver_later
        render json: { status: 'ok', nickname: credential.nickname }, status: :created
      rescue WebAuthn::Error, ArgumentError, ActionController::ParameterMissing
        failed
      end

      # A short-lived proof that this account just signed in with its password in the app.
      def self.setup_token_for(user)
        setup_verifier.generate(user.id, expires_in: SETUP_WINDOW)
      end

      def self.challenge_verifier
        Rails.application.message_verifier('api/v1/passkey_registration_challenge')
      end

      def self.setup_verifier
        Rails.application.message_verifier('api/v1/passkey_setup')
      end

      private

      def setup_token_valid?
        token = params[:setup_token].to_s
        token.present? && self.class.setup_verifier.verified(token) == current_user.id
      end

      def spend_challenge(challenge)
        Rails.cache.write("api/v1/passkey_registration_challenge/#{Digest::SHA256.hexdigest(challenge)}", true,
                          unless_exist: true, expires_in: PasskeyAssertion::CHALLENGE_LIFETIME)
      end

      def failed(details = nil)
        render_error(:unprocessable_content, 'passkey_not_added', "Couldn't add that passkey. Try again.", details: details)
      end
    end
  end
end
