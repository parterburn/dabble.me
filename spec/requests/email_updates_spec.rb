require 'rails_helper'

RSpec.describe 'Unsubscribing from updates', type: :request do
  let(:user) { FactoryBot.create(:user, frequency: %w[Mon Wed]) }
  let(:token) { user.email_settings_token }

  it 'shows a confirmation page without unsubscribing' do
    get email_updates_path(token: token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Unsubscribe from updates')
    expect(user.reload.send_updates).to be(true)
  end

  it 'unsubscribes on POST with no login or CSRF token, and leaves journal emails alone' do
    ActionController::Base.allow_forgery_protection = true
    post email_updates_path(token: token), params: { 'List-Unsubscribe' => 'One-Click' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("You're unsubscribed from updates")
    expect(user.reload.send_updates).to be(false)
    expect(user.frequency).to eq(%w[Mon Wed])
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it 'rejects a bad token' do
    post email_updates_path(token: 'nope')

    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload.send_updates).to be(true)
  end

  describe 'email settings' do
    it 'turns updates off and back on from the settings link' do
      put unsubscribe_path(token: token), params: { user: { send_updates: '0' }, frequency: { 'Mon' => '1' } }
      expect(user.reload.send_updates).to be(false)

      put unsubscribe_path(token: token), params: { user: { send_updates: '1' }, frequency: { 'Mon' => '1' } }
      expect(user.reload.send_updates).to be(true)
    end

    it 'turns updates off with "unsubscribe from all emails"' do
      put unsubscribe_path(token: token), params: { user: { send_updates: '1' }, unsub_all: 'yes' }

      expect(user.reload.send_updates).to be(false)
      expect(user.frequency).to eq([])
    end
  end
end
