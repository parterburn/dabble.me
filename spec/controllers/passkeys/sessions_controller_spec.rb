require 'rails_helper'

RSpec.describe Passkeys::SessionsController, type: :controller do
  describe 'GET #new' do
    it 'returns a WebAuthn challenge for an unknown email (no enumeration)' do
      get :new, params: { email: 'nobody@example.com' }, format: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['challenge']).to be_present
      expect(body['allowCredentials']).to eq([])
      expect(session[:webauthn_authentication_user_id]).to be_nil
      expect(session[:webauthn_authentication_challenge]).to eq(body['challenge'])
    end

    it 'returns the same response shape for a known user without passkeys' do
      user = create(:user)

      get :new, params: { email: user.email }, format: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['challenge']).to be_present
      expect(body['allowCredentials']).to eq([])
      expect(session[:webauthn_authentication_user_id]).to eq(user.id)
    end

    it 'includes allowCredentials for a known user with a passkey' do
      user = create(:user)
      credential = create(:webauthn_credential, user: user)

      get :new, params: { email: user.email }, format: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['allowCredentials']).to contain_exactly(credential.external_id)
      expect(session[:webauthn_authentication_user_id]).to eq(user.id)
    end
  end

  describe 'POST #create' do
    it 'returns a generic error when there is no authentication session' do
      allow(::WebAuthn::Credential).to receive(:from_get).and_return(instance_double(::WebAuthn::PublicKeyCredentialWithAssertion, id: 'cred'))

      post :create, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to eq('errors' => ['Authentication failed'])
    end

    it 'returns a generic error when the session user no longer exists' do
      allow(::WebAuthn::Credential).to receive(:from_get).and_return(instance_double(::WebAuthn::PublicKeyCredentialWithAssertion, id: 'cred'))
      session[:webauthn_authentication_user_id] = -1
      session[:webauthn_authentication_challenge] = 'challenge'

      post :create, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to eq('errors' => ['Authentication failed'])
      expect(session[:webauthn_authentication_user_id]).to be_nil
    end
  end
end
