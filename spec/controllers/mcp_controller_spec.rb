require "rails_helper"

RSpec.describe McpController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers
  include_context "has all objects"

  before do
    request.env['HTTP_AUTHORIZATION'] = "Bearer #{token}" if defined?(token)
  end

  describe 'create' do
    context 'without a valid token' do
      it 'returns unauthorized' do
        post :create, params: { jsonrpc: '2.0', id: 1, method: 'initialize' }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with an enabled token' do
      let(:token) do
        paid_user.generate_otp_secret
        paid_user.update!(otp_enabled: true, otp_enabled_on: Time.current)
        paid_user.generate_mcp_token!
      end

      it 'initializes the MCP server' do
        post :create, params: { jsonrpc: '2.0', id: 1, method: 'initialize' }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig('result', 'serverInfo', 'name')).to eq('dabble-me')
      end

      it 'searches only the authenticated user entries' do
        paid_entry.update!(body: 'I saw the northern lights in Iceland #travel')
        not_my_entry.update!(body: 'I saw the northern lights too #travel')

        post :create, params: {
          jsonrpc: '2.0',
          id: 2,
          method: 'tools/call',
          params: {
            name: 'search_entries',
            arguments: { query: 'northern lights' }
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body).not_to have_key('error')
        entries = body.dig('result', 'structuredContent', 'entries')
        expect(entries.length).to eq(1)
        expect(entries.first['id']).to eq(paid_entry.id)
        expect(entries.first['excerpt']).to include('northern lights')
      end

      it 'returns aggregate analysis' do
        paid_entry.update!(body: 'First #gratitude note')
        paid_user.entries.create!(body: 'Second #gratitude note', date: 1.day.ago)

        post :create, params: {
          jsonrpc: '2.0',
          id: 3,
          method: 'tools/call',
          params: {
            name: 'analyze_entries',
            arguments: {}
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        structured = body.dig('result', 'structuredContent')
        expect(structured['total_entries']).to eq(2)
        expect(structured['top_hashtags'].first).to include('hashtag' => 'gratitude', 'count' => 2)
      end
    end

    context 'when the user no longer meets security requirements' do
      let(:token) do
        paid_user.generate_otp_secret
        paid_user.update!(otp_enabled: true, otp_enabled_on: Time.current)
        paid_user.generate_mcp_token!
      end

      it 'rejects the request' do
        paid_user.update!(otp_enabled: false)

        post :create, params: { jsonrpc: '2.0', id: 4, method: 'initialize' }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the MCP token has expired' do
      let(:token) do
        travel_to(Time.zone.local(2025, 1, 1, 12, 0, 0)) do
          paid_user.generate_otp_secret
          paid_user.update!(otp_enabled: true, otp_enabled_on: Time.current)
          paid_user.generate_mcp_token!
        end
      end

      it 'rejects the request and revokes stored credentials' do
        travel_to(Time.zone.local(2025, 8, 1, 12, 0, 0)) do
          post :create, params: { jsonrpc: '2.0', id: 5, method: 'initialize' }, as: :json
        end

        expect(response).to have_http_status(:unauthorized)
        expect(paid_user.reload.mcp_token_digest).to be_blank
        expect(paid_user.mcp_enabled).to eq(false)
      end
    end
  end
end
