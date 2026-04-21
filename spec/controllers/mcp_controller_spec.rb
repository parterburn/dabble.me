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

      it 'initializes the MCP server with access_token query (Claude-style URL)' do
        request.env.delete("HTTP_AUTHORIZATION")

        post :create, params: { jsonrpc: "2.0", id: 1, method: "initialize", access_token: token }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig("result", "serverInfo", "name")).to eq("dabble-me")
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

      it 'defaults date to today in the user timezone when omitted' do
        denver = ActiveSupport::TimeZone['America/Denver']
        travel_to denver.local(2030, 1, 15, 14, 0, 0) do
          paid_user.update!(send_timezone: 'America/Denver')
          paid_user.entries.delete_all
          # Token from the shared `before` is issued at real time; re-issue inside frozen time so it is not expired.
          request.env['HTTP_AUTHORIZATION'] = "Bearer #{paid_user.generate_mcp_token!}"

          post :create, params: {
            jsonrpc: '2.0',
            id: 35,
            method: 'tools/call',
            params: {
              name: 'create_entry',
              arguments: { 'body' => 'Today entry without date param' }
            }
          }, as: :json
        end

        expect(response).to have_http_status(:ok)
        structured = JSON.parse(response.body).dig('result', 'structuredContent')
        expect(structured['success']).to eq(true)
        expect(structured['entry']['date']).to eq('2030-01-15')
      end

      it 'creates a new entry on an unused date' do
        post :create, params: {
          jsonrpc: '2.0',
          id: 31,
          method: 'tools/call',
          params: {
            name: 'create_entry',
            arguments: {
              'date' => '2099-06-15',
              'body' => "Line one.\n\nLine two with #mcp"
            }
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        structured = body.dig('result', 'structuredContent')
        expect(structured['success']).to eq(true)
        expect(structured['merged']).to eq(false)
        expect(structured['entry']['date']).to eq('2099-06-15')
        expect(structured['entry']['excerpt']).to include('Line one')
        expect(structured['entry']['hashtags']).to include('mcp')

        created = paid_user.entries.find(structured['entry']['id'])
        expect(created.body).to include('<p>Line one.</p>')
        expect(created.body).not_to include('<script>')
      end

      it 'appends when merge_with_existing is true and the day exists' do
        day = paid_entry.date.to_date.iso8601
        prior_body = paid_entry.body

        post :create, params: {
          jsonrpc: '2.0',
          id: 32,
          method: 'tools/call',
          params: {
            name: 'create_entry',
            arguments: {
              'date' => day,
              'body' => 'Appended via MCP',
              'merge_with_existing' => true
            }
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        structured = JSON.parse(response.body).dig('result', 'structuredContent')
        expect(structured['success']).to eq(true)
        expect(structured['merged']).to eq(true)
        expect(structured['entry']['id']).to eq(paid_entry.id)

        paid_entry.reload
        expect(paid_entry.body).to start_with(prior_body)
        expect(paid_entry.body).to include('<hr>')
        expect(paid_entry.body).to include('Appended via MCP')
      end

      it 'returns a structured error when merge_with_existing is false and the day exists' do
        day = paid_entry.date.to_date.iso8601

        post :create, params: {
          jsonrpc: '2.0',
          id: 33,
          method: 'tools/call',
          params: {
            name: 'create_entry',
            arguments: {
              'date' => day,
              'body' => 'Should not save',
              'merge_with_existing' => false
            }
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        structured = JSON.parse(response.body).dig('result', 'structuredContent')
        expect(structured['success']).to eq(false)
        expect(structured['errors'].first).to include('already exists')
      end

      it 'returns validation-style errors for invalid input' do
        post :create, params: {
          jsonrpc: '2.0',
          id: 34,
          method: 'tools/call',
          params: {
            name: 'create_entry',
            arguments: {
              'date' => 'not-a-date',
              'body' => 'x'
            }
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        structured = JSON.parse(response.body).dig('result', 'structuredContent')
        expect(structured['success']).to eq(false)
        expect(structured['errors'].first).to include('YYYY-MM-DD')
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
