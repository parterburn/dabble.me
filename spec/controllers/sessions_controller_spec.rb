require 'rails_helper'

RSpec.describe SessionsController, type: :controller do
  include_context 'has all objects'

  before do
    request.env['devise.mapping'] = Devise.mappings[:user]
  end

  describe 'create' do
    it 'cancels pending deletion when the user signs in' do
      user.update_column(:deleted_at, Time.current)

      post :create, params: { user: { email: user.email, password: user.password } }

      expect(user.reload.deleted_at).to be_nil
      expect(flash[:notice]).to eq(I18n.t('devise.sessions.deletion_cancelled'))
    end
  end
end

RSpec.describe 'OTP authentication flow', type: :request do
  let(:user) { create(:user) }

  it 'challenges OTP-enabled users on sign-in and signs them in with a valid token' do
    user.generate_otp_secret
    user.update!(otp_enabled: true, otp_enabled_on: Time.current)

    post user_session_path, params: { user: { email: user.email, password: user.password } }

    expect(response).to have_http_status(:found)
    challenge = user.reload.otp_session_challenge
    expect(challenge).to be_present
    expect(response.headers['Location']).to include(user_otp_credential_path(challenge: challenge))

    get user_otp_credential_path(challenge: challenge)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t('prompt', scope: 'devise.otp.submit_token'))

    totp_code = ROTP::TOTP.new(user.otp_auth_secret).now
    put user_otp_credential_path, params: {
      challenge: challenge,
      recovery: 'false',
      token: totp_code
    }

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response).to redirect_to(latest_entry_path)
  end

  it 'allows enabling and resetting OTP from the custom token settings view' do
    sign_in user

    get user_otp_token_path
    expect(response).to have_http_status(:ok)
    expect(user.reload.otp_auth_secret).to be_present

    totp_code = ROTP::TOTP.new(user.otp_auth_secret).now
    post validate_otp_path, params: { user: { token: totp_code } }
    expect(user.reload.otp_enabled).to be(true)

    get user_otp_token_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t('title', scope: 'devise.otp.otp_tokens.recovery'))

    old_secret = user.otp_auth_secret
    delete user_otp_token_path
    expect(response).to redirect_to(user_otp_token_path)
    expect(user.reload.otp_enabled).to be(false)
    expect(user.otp_auth_secret).to be_nil

    get user_otp_token_path
    expect(response).to have_http_status(:ok)
    expect(user.reload.otp_auth_secret).to be_present
    expect(user.otp_auth_secret).not_to eq(old_secret)
  end
end
