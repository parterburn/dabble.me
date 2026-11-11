require 'webauthn'

# Confirms a passkey for the account that is already signed in. Admin
# sessions need this every AdminAccess::PASSKEY_FRESHNESS (see
# ApplicationController#require_admin_passkey). Only the signed-in user's
# own passkeys are accepted.
class Passkeys::VerificationsController < ApplicationController
  before_action :authenticate_user!

  FAILED = { errors: ["That passkey couldn't be confirmed. Try again."] }.freeze
  CHALLENGE_KEY = :webauthn_verification_challenge

  def new
    return redirect_to(security_path) unless current_user.webauthn_credentials.exists?
  end

  def options
    options = ::WebAuthn::Credential.options_for_get(
      allow: current_user.webauthn_credentials.pluck(:external_id),
      user_verification: "required"
    )
    session[CHALLENGE_KEY] = options.challenge

    render json: options
  end

  def create
    challenge = session.delete(CHALLENGE_KEY)
    return failed if challenge.blank?

    webauthn_credential = ::WebAuthn::Credential.from_get(params)
    credential = current_user.webauthn_credentials.find_by(external_id: webauthn_credential.id)
    return failed unless credential

    webauthn_credential.verify(
      challenge,
      public_key: credential.public_key,
      sign_count: credential.sign_count,
      user_verification: true
    )

    credential.update!(sign_count: webauthn_credential.sign_count)
    AdminAccess.record_passkey!(session, current_user)

    render json: { status: "ok", redirect_url: AdminAccess.take_return_to!(session) || after_sign_in_path_for(current_user) }
  rescue WebAuthn::Error, ArgumentError
    failed
  end

  private

  def failed
    render json: FAILED, status: :unprocessable_content
  end
end
