require 'webauthn'

class Passkeys::SessionsController < ApplicationController
  AUTH_FAILED = { errors: ["Authentication failed"] }.freeze

  def new
    user = User.find_by(email: params[:email].to_s.strip.downcase)
    credential_ids = user ? user.webauthn_credentials.pluck(:external_id) : []

    # Always return a challenge so unknown emails are indistinguishable from
    # known accounts (including those with no passkeys registered).
    options = ::WebAuthn::Credential.options_for_get(
      allow_credentials: credential_ids,
      user_verification: "required"
    )

    session[:webauthn_authentication_challenge] = options.challenge
    session[:webauthn_authentication_user_id] = user&.id

    render json: options
  end

  def create
    webauthn_credential = ::WebAuthn::Credential.from_get(params)
    user_id = session[:webauthn_authentication_user_id]
    challenge = session[:webauthn_authentication_challenge]

    begin
      return render json: AUTH_FAILED, status: :unprocessable_entity unless user_id

      user = User.find_by(id: user_id)
      return render json: AUTH_FAILED, status: :unprocessable_entity unless user

      credential = user.webauthn_credentials.find_by(external_id: webauthn_credential.id)
      return render json: AUTH_FAILED, status: :unprocessable_entity unless credential

      webauthn_credential.verify(
        challenge,
        public_key: credential.public_key,
        sign_count: credential.sign_count
      )

      credential.update!(sign_count: webauthn_credential.sign_count)
      sign_in(user)

      render json: { status: "ok", redirect_url: root_path }, status: :ok
    rescue WebAuthn::VerificationError
      render json: AUTH_FAILED, status: :unprocessable_entity
    ensure
      session.delete(:webauthn_authentication_challenge)
      session.delete(:webauthn_authentication_user_id)
    end
  end
end
