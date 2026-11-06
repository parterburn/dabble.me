# frozen_string_literal: true

require "webauthn/fake_client"

# Real WebAuthn ceremonies against WebAuthn::FakeClient, so specs exercise
# signature, challenge, user-handle and user-verification checks end to end.
module PasskeyHelpers
  def passkey_client
    @passkey_client ||= WebAuthn::FakeClient.new(WebAuthn.configuration.allowed_origins.first)
  end

  # Registers a passkey on +client+ for +user+ and stores it the way
  # Passkeys::RegistrationsController#create does.
  def register_passkey(user, client: passkey_client)
    challenge = WebAuthn.configuration.encoder.encode(SecureRandom.random_bytes(32))
    created = WebAuthn::Credential.from_create(client.create(challenge: challenge, user_verified: true))
    created.verify(challenge, user_verification: true)

    user.webauthn_credentials.create!(
      external_id: created.id,
      public_key: created.public_key,
      nickname: "Test passkey",
      sign_count: created.sign_count
    )
  end

  # The assertion a browser would post after the user picks the passkey.
  def passkey_assertion(challenge:, user_handle:, user_verified: true, client: passkey_client)
    client.get(challenge: challenge, user_handle: user_handle, user_verified: user_verified)
  end
end

RSpec.configure do |config|
  config.include PasskeyHelpers
end
