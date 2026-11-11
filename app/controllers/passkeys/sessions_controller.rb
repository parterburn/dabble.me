require 'webauthn'

# Passkey sign-in with discoverable credentials: the browser offers the
# passkey (email-field autofill or the "Log in with Passkey" button) and the
# assertion identifies the account. The server never looks an account up by
# email here, so it never tells an unauthenticated caller which emails exist
# or which credential IDs belong to them.
class Passkeys::SessionsController < ApplicationController
  AUTH_FAILED = { errors: ["Authentication failed"] }.freeze

  def new
    options = ::WebAuthn::Credential.options_for_get(user_verification: "required")
    session[:webauthn_authentication_challenge] = options.challenge

    render json: options
  end

  def create
    # Single use: a challenge is gone once an assertion has been checked against it.
    challenge = session.delete(:webauthn_authentication_challenge)
    return auth_failed if challenge.blank?

    webauthn_credential = ::WebAuthn::Credential.from_get(params)
    credential = WebauthnCredential.find_by(external_id: webauthn_credential.id)
    return auth_failed unless credential && owned_by_handle?(credential, webauthn_credential)

    # A passkey stands in for both the password and the second factor, so the
    # authenticator must have verified the user (biometric or PIN), not just
    # registered a tap.
    webauthn_credential.verify(
      challenge,
      public_key: credential.public_key,
      sign_count: credential.sign_count,
      user_verification: true
    )

    credential.update!(sign_count: webauthn_credential.sign_count)
    user = credential.user
    # Remembered only when the sign-in page's "Stay logged in" box is ticked.
    user.remember_me = ActiveModel::Type::Boolean.new.cast(params[:remember_me])
    sign_in(user)
    # Signing in with a passkey is itself the check admin sessions need.
    AdminAccess.record_passkey!(session, user)

    render json: { status: "ok", redirect_url: after_sign_in_path_for(user) }, status: :ok
  rescue WebAuthn::Error, ArgumentError
    auth_failed
  end

  private

  def auth_failed
    render json: AUTH_FAILED, status: :unprocessable_content
  end

  # Discoverable credentials return the user handle set at registration
  # (Passkeys::RegistrationsController#new uses the user's id).
  def owned_by_handle?(credential, webauthn_credential)
    handle = webauthn_credential.raw_user_handle
    handle.present? && ActiveSupport::SecurityUtils.secure_compare(handle, credential.user_id.to_s)
  end
end
