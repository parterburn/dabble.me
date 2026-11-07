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
      exclude_credentials: current_user.webauthn_credentials.pluck(:external_id),
      # Discoverable ("resident") credentials can be offered by email-field
      # autofill and sign in without an email lookup; see Passkeys::SessionsController.
      authenticator_selection: { resident_key: "required", user_verification: "required" }
    )

    session[:webauthn_registration_challenge] = options.challenge

    render json: options
  end

  def create
    unless current_user.valid_password?(params[:current_password])
      render json: { errors: ["Incorrect current password."] }, status: :unprocessable_content
      return
    end

    webauthn_credential = ::WebAuthn::Credential.from_create(params)

    begin
      webauthn_credential.verify(session[:webauthn_registration_challenge], user_verification: true)

      credential = current_user.webauthn_credentials.build(
        external_id: webauthn_credential.id,
        public_key: webauthn_credential.public_key,
        nickname: params[:nickname] || "Passkey #{current_user.webauthn_credentials.count + 1}",
        sign_count: webauthn_credential.sign_count
      )

      if credential.save
        UserMailer.passkey_added(current_user, credential.nickname).deliver_later
        render json: { status: "ok" }, status: :ok
      else
        render json: { errors: credential.errors.full_messages }, status: :unprocessable_content
      end
    rescue WebAuthn::VerificationError => e
      render json: { errors: [e.message] }, status: :unprocessable_content
    ensure
      session.delete(:webauthn_registration_challenge)
    end
  end

  def destroy
    credential = current_user.webauthn_credentials.find(params[:id])
    credential.destroy
    current_user.reload
    current_user.revoke_doorkeeper_access_tokens!(keep_mobile_app: true) unless current_user.mcp_security_requirements_met?
    redirect_to security_path, notice: "Passkey removed."
  end
end
