# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SHA-1 to SHA-256 cookie rotation', type: :request do
  let(:secret_key_base) { Rails.application.secret_key_base }
  let(:sha1_key_generator) do
    ActiveSupport::KeyGenerator.new(
      secret_key_base, iterations: 1000, hash_digest_class: OpenSSL::Digest::SHA1
    )
  end

  def build_CookieJar(raw_cookies = {})
    env = Rails.application.env_config.merge(
      Rack::MockRequest.env_for('/', 'HTTP_COOKIE' => raw_cookies.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('; '))
    )
    req = ActionDispatch::Request.new(env)
    req.cookie_jar
  end

  it 'transparently decrypts and rotates SHA-1 encrypted cookies under Rails 7.2 defaults' do
    expect(Rails.application.config.active_support.key_generator_hash_digest_class).to eq(OpenSSL::Digest::SHA256)

    salt = Rails.application.config.action_dispatch.authenticated_encrypted_cookie_salt
    key_len = ActiveSupport::MessageEncryptor.key_len
    legacy_secret = sha1_key_generator.generate_key(salt, key_len)
    legacy_encryptor = ActiveSupport::MessageEncryptor.new(
      legacy_secret,
      cipher: 'aes-256-gcm',
      serializer: ActiveSupport::MessageEncryptor::NullSerializer
    )

    payload = { 'user_id' => 42, 'session_id' => 'legacy-sha1-session' }.to_json
    legacy_ciphertext = legacy_encryptor.encrypt_and_sign(payload, purpose: 'cookie._dabbleme_session')

    jar = build_CookieJar('_dabbleme_session' => legacy_ciphertext)
    expect(jar.encrypted['_dabbleme_session']).to eq('user_id' => 42, 'session_id' => 'legacy-sha1-session')

    # Verify the rotated value is re-encrypted with the SHA-256 key
    sha256_secret = Rails.application.key_generator.generate_key(salt, key_len)
    sha256_encryptor = ActiveSupport::MessageEncryptor.new(
      sha256_secret,
      cipher: 'aes-256-gcm',
      serializer: ActiveSupport::MessageEncryptor::NullSerializer
    )
    rotated_raw = jar['_dabbleme_session']
    expect(rotated_raw).not_to eq(legacy_ciphertext)
    expect(JSON.parse(sha256_encryptor.decrypt_and_verify(rotated_raw, purpose: 'cookie._dabbleme_session'))).to eq(
      'user_id' => 42, 'session_id' => 'legacy-sha1-session'
    )
  end

  it 'transparently verifies and rotates SHA-1 signed cookies under Rails 7.2 defaults' do
    salt = Rails.application.config.action_dispatch.signed_cookie_salt
    legacy_secret = sha1_key_generator.generate_key(salt)
    legacy_verifier = ActiveSupport::MessageVerifier.new(
      legacy_secret,
      digest: 'SHA1',
      serializer: ActiveSupport::MessageEncryptor::NullSerializer
    )

    payload = 'trusted-device-token'.to_json
    legacy_signed = legacy_verifier.generate(payload, purpose: 'cookie.otp_TrustedDevice')

    jar = build_CookieJar('otp_TrustedDevice' => legacy_signed)
    expect(jar.signed['otp_TrustedDevice']).to eq('trusted-device-token')

    sha256_secret = Rails.application.key_generator.generate_key(salt)
    sha256_verifier = ActiveSupport::MessageVerifier.new(
      sha256_secret,
      digest: 'SHA1',
      serializer: ActiveSupport::MessageEncryptor::NullSerializer
    )
    rotated_raw = jar['otp_TrustedDevice']
    expect(rotated_raw).not_to eq(legacy_signed)
    expect(JSON.parse(sha256_verifier.verified(rotated_raw, purpose: 'cookie.otp_TrustedDevice'))).to eq('trusted-device-token')
  end
end
