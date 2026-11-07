# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkey registration", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def registration_options
    get new_passkeys_registration_path, as: :json
    JSON.parse(response.body)
  end

  it "asks for a discoverable passkey with user verification so autofill can offer it" do
    options = registration_options

    expect(options["authenticatorSelection"]).to include("residentKey" => "required", "userVerification" => "required")
  end

  it "saves a passkey that verified the user" do
    options = registration_options
    attestation = passkey_client.create(challenge: options["challenge"], user_verified: true)

    expect {
      post passkeys_registrations_path, params: attestation.merge(nickname: "Laptop", current_password: user.password), as: :json
    }.to change { user.webauthn_credentials.count }.by(1)
    expect(response).to have_http_status(:ok)
  end

  it "refuses a passkey that did not verify the user" do
    options = registration_options
    attestation = passkey_client.create(challenge: options["challenge"], user_verified: false)

    expect {
      post passkeys_registrations_path, params: attestation.merge(nickname: "Key", current_password: user.password), as: :json
    }.not_to change { user.webauthn_credentials.count }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
