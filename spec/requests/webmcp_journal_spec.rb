# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'WebMCP journal session tools', type: :request do
  include_context 'has all objects'

  it 'rejects anonymous journal tool calls without leaking another user' do
    post '/webmcp/journal/search', params: { query: 'burnout' }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['isError']).to eq(true)
  end

  it 'searches only the signed-in PRO account and never another user' do
    paid_entry.update!(body: 'I mentioned burnout after the long week.')
    not_my_entry.update!(body: 'I mentioned burnout too, but this is someone else.')
    sign_in paid_user

    post '/webmcp/journal/search', params: { query: 'burnout' }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload['isError']).to eq(false)
    excerpts = payload.dig('data', 'entries').map { |row| row['excerpt'] }
    expect(excerpts.join).to include('burnout after the long week')
    expect(excerpts.join).not_to include('someone else')
    expect(payload.dig('data', 'entries').first['url']).to match(%r{\A/entries/\d+/\d+/\d+\z})
  end

  it 'lets any signed-in user list their own entries' do
    sign_in user

    post '/webmcp/journal/list', params: { limit: 5 }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }

    expect(response).to have_http_status(:ok)
    ids = JSON.parse(response.body).dig('data', 'entries').map { |row| row['id'] }
    expect(ids).to include(entry.id)
    expect(ids).not_to include(paid_entry.id)
  end

  it 'requires PRO for search and analyze' do
    sign_in user

    post '/webmcp/journal/search', params: { query: 'hello' }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:forbidden)

    post '/webmcp/journal/analyze', params: {}.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not require passkey or 2FA for in-page session tools' do
    expect(paid_user.mcp_security_requirements_met?).to eq(false)
    sign_in paid_user

    get '/webmcp/journal/session'

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig('data', 'is_pro')).to eq(true)
  end

  it 'embeds signed-in WebMCP tool config on journal pages' do
    sign_in paid_user
    get '/entries/new'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('"signedIn":true')
    expect(response.body).to include('search_journal_entries')
    expect(response.body).to include('draft_journal_entry')
    expect(response.body).to include('toolname="write_journal_entry"')
  end
end
