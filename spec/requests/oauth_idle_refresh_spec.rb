# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Refreshing an idle OAuth connection' do
  let(:user) { create(:user) }
  let(:claude) do
    Doorkeeper::Application.create!(name: 'Claude', redirect_uri: 'https://claude.ai/api/mcp/auth_callback',
                                    scopes: 'mcp:access', confidential: false)
  end
  let(:mobile_app) { MobileApp.ensure_application! }

  def token(application, created_at:)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id,
                                    scopes: application.scopes.to_s, expires_in: 1.day.to_i,
                                    use_refresh_token: true, created_at: created_at)
  end

  def refresh(token, application)
    post '/oauth/token', params: { grant_type: 'refresh_token', refresh_token: token.plaintext_refresh_token,
                                   client_id: application.uid }
  end

  def json
    JSON.parse(response.body)
  end

  it 'refuses and revokes a connector refresh token unused for 30 days' do
    stale = token(claude, created_at: 31.days.ago)

    expect { refresh(stale, claude) }.not_to(change { Doorkeeper::AccessToken.count })
    expect(response).to have_http_status(:bad_request)
    expect(json['error']).to eq('invalid_grant')
    expect(stale.reload).to be_revoked
  end

  it 'renews a connector used within 30 days, which restarts the clock' do
    recent = token(claude, created_at: 29.days.ago)

    refresh(recent, claude)
    expect(response).to have_http_status(:ok)
    renewed = Doorkeeper::AccessToken.by_token(json['access_token'])
    expect(renewed.created_at).to be > 1.minute.ago
    expect(recent.reload).to be_revoked
  end

  it 'gives the iOS app a year before it has to sign in again' do
    month_old = token(mobile_app, created_at: 60.days.ago)
    refresh(month_old, mobile_app)
    expect(response).to have_http_status(:ok)

    year_old = token(mobile_app, created_at: 366.days.ago)
    refresh(year_old, mobile_app)
    expect(response).to have_http_status(:bad_request)
    expect(year_old.reload).to be_revoked
  end
end
