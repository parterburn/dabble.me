require 'webauthn'

class Passkeys::SessionsController < ApplicationController
  def new
    user = User.find_by(email: params[:email])

    if user
      options = ::WebAuthn::Credential.options_for_get(
        allow_credentials: user.webauthn_credentials.pluck(:external_id),
        user_verification: "required"
      )

      session[:webauthn_authentication_challenge] = options.challenge
      session[:webauthn_authentication_user_id] = user.id

      render json: options
    else
      render json: { errors: ["User not found"] }, status: :not_found
    end
  end

  def create
    webauthn_credential = ::WebAuthn::Credential.from_get(params)

    user_id = session[:webauthn_authentication_user_id]
    return render json: { errors: ["Authentication session expired"] }, status: :unprocessable_entity unless user_id

    user = User.find_by(id: user_id)
    return render json: { errors: ["User not found"] }, status: :not_found unless user

    credential = user.webauthn_credentials.find_by(external_id: webauthn_credential.id)
    return render json: { errors: ["Credential not found"] }, status: :unprocessable_entity unless credential

    begin
      webauthn_credential.verify(
        session[:webauthn_authentication_challenge],
        public_key: credential.public_key,
        sign_count: credential.sign_count
      )

      credential.update!(sign_count: webauthn_credential.sign_count)
      sign_in(user)

      render json: { status: "ok", redirect_url: root_path }, status: :ok
    rescue WebAuthn::VerificationError => e
      render json: { errors: [e.message] }, status: :unprocessable_entity
    ensure
      session.delete(:webauthn_authentication_challenge)
      session.delete(:webauthn_authentication_user_id)
    end
  end
end
