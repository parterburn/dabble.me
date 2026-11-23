# frozen_string_literal: true

require 'rails_helper'

# After a refresh, nothing from the old token works: not its access token, not its refresh
# token, and a refresh token is never accepted as a bearer token. Both bearer endpoints
# (/mcp and /api/v1) go through doorkeeper_authorize!, which checks revoked and expired.
RSpec.describe 'Rotated and revoked OAuth tokens' do
  let(:user) { create(:user) }
  let(:connector) do
    Doorkeeper::Application.create!(name: 'Claude', redirect_uri: 'https://claude.ai/api/mcp/auth_callback',
                                    scopes: 'mcp:access', confidential: false)
  end
  let(:mobile_app) { MobileApp.ensure_application! }

  def issue(application)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id,
                                    scopes: application.scopes.to_s, expires_in: 1.day.to_i, use_refresh_token: true)
  end

  def refresh(refresh_token, application)
    post '/oauth/token', params: { grant_type: 'refresh_token', refresh_token: refresh_token, client_id: application.uid }
  end

  def call_mcp(bearer)
    post '/mcp', params: { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'list_entries', arguments: {} } },
                 headers: { 'Authorization' => "Bearer #{bearer}" }, as: :json
    response.status
  end

  def call_api(bearer)
    get '/api/v1/me', headers: { 'Authorization' => "Bearer #{bearer}" }
    response.status
  end

  {
    'MCP connector' => [:connector, :call_mcp],
    'iOS app' => [:mobile_app, :call_api]
  }.each do |label, (app_name, caller)|
    context "for the #{label}" do
      let(:application) { send(app_name) }

      it 'kills the old access and refresh tokens once the client refreshes' do
        old = issue(application)
        old_access = old.plaintext_token
        old_refresh = old.plaintext_refresh_token
        expect(send(caller, old_access)).to eq(200)

        refresh(old_refresh, application)
        expect(response).to have_http_status(:ok)
        new_access = JSON.parse(response.body)['access_token']

        expect(send(caller, old_access)).to eq(401)
        expect(send(caller, old_refresh)).to eq(401)
        refresh(old_refresh, application)
        expect(response).to have_http_status(:bad_request)
        expect(send(caller, new_access)).to eq(200)
      end

      it 'refuses a refresh token used as a bearer token' do
        expect(send(caller, issue(application).plaintext_refresh_token)).to eq(401)
      end

      it 'refuses revoked and expired access tokens' do
        revoked = issue(application)
        access = revoked.plaintext_token
        revoked.revoke
        expect(send(caller, access)).to eq(401)

        expired = issue(application)
        access = expired.plaintext_token
        expired.update_columns(created_at: 2.days.ago)
        expect(send(caller, access)).to eq(401)
      end
    end
  end
end
