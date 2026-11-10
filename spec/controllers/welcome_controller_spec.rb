require 'rails_helper'

RSpec.describe WelcomeController, type: :controller do
  include_context 'has all objects'

  describe 'index' do
    it 'should show the welcome page to non-logged in users' do
      get :index
      expect(response.status).to eq 200
      expect(response.body).to have_content("A journal you might actually stick with.")
    end

    it 'calls past entries Rewind, with the Slab backward icon and a sample heading like the real email' do
      get :index

      expect(response.body).to have_css('h3', text: 'Rewind')
      expect(response.body).to have_css('.slab-icon.slab-icon--backward', count: 2)
      expect(response.body).to have_content('Rewind past entries')
      expect(response.body).not_to match(/blasts? from the past|Remember this\?/i)
      # The sample entry is picked at random: 6 months back or this day years ago.
      expect(response.body).to match(/(Rewind 6 months|On this day (3|10) years ago) • \w{3}, \w{3} \d{1,2}, \d{4} you wrote\.\.\./)
    end

    it 'should redirect to latest entry for logged in users' do
      entry
      not_my_entry
      sign_in user
      get :index
      expect(response.status).to eq 302
      expect(response).to redirect_to(latest_entry_url)
    end
  end

  describe 'subscribe' do
    it 'calls the yearly stats page Writing Stats by Year, not Year in Review' do
      get :subscribe

      expect(response.body).to have_css('h3', text: 'Writing Stats by Year')
      expect(response.body).not_to match(/Year in Review/i)
    end
  end

  describe 'mcp_server' do
    it 'renders the plain-language AI Connector guide' do
      get :mcp_server

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        '<title>Dabble Me AI Connector: Use Your Journal with ChatGPT and Claude — Dabble me.</title>'
      )
    end
  end

  describe 'mcp_server_developers' do
    it 'renders documentation from the MCP tool schemas' do
      get :mcp_server_developers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<title>Dabble Me MCP Server: Technical Reference — Dabble me.</title>')
      expect(response.body).to have_content('search_entries')
      expect(response.body).to have_content('query (required)')
    end
  end
end
