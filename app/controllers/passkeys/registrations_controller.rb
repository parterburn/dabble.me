require 'webauthn'

class Passkeys::RegistrationsController < ApplicationController
  before_action :authenticate_user!

  def new
    options = ::WebAuthn::Credential.options_for_create(
      user: {
        id: Base64.urlsafe_encode64(current_user.id.to_s, padding: false),
        name: current_user.email,
        display_name: current_user.full_name_or_email
      },
      exclude_credentials: current_user.webauthn_credentials.pluck(:external_id)
    )

    session[:webauthn_registration_challenge] = options.challenge

    render json: options
  end

  def create
    webauthn_credential = ::WebAuthn::Credential.from_create(params)

    begin
      webauthn_credential.verify(session[:webauthn_registration_challenge])

      credential = current_user.webauthn_credentials.build(
        external_id: webauthn_credential.id,
        public_key: webauthn_credential.public_key,
        nickname: params[:nickname] || "Passkey #{current_user.webauthn_credentials.count + 1}",
        sign_count: webauthn_credential.sign_count
      )

      if credential.save
        render json: { status: "ok" }, status: :ok
      else
        render json: { errors: credential.errors.full_messages }, status: :unprocessable_entity
      end
    rescue WebAuthn::VerificationError => e
      render json: { errors: [e.message] }, status: :unprocessable_entity
    ensure
      session.delete(:webauthn_registration_challenge)
    end
  end

  def destroy
    credential = current_user.webauthn_credentials.find(params[:id])
    credential.destroy
    cookies.delete(:dabble_passkey_user_hint) if current_user.webauthn_credentials.none?
    redirect_to security_path, notice: "Passkey removed."
  end
end
