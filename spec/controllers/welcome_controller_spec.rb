require 'rails_helper'

RSpec.describe WelcomeController, type: :controller do
  include_context 'has all objects'

  describe 'index' do
    it 'should show the welcome page to non-logged in users' do
      get :index
      expect(response.status).to eq 200
      expect(response.body).to have_content("A journal you might actually stick with.")
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

  describe 'mcp_server' do
    it 'renders documentation from the MCP tool schemas' do
      get :mcp_server

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        '<title>Dabble Me MCP Server: Connect Your Journal to ChatGPT and Claude — Dabble me.</title>'
      )
      expect(response.body).to have_content('search_entries')
      expect(response.body).to have_content('query (required)')
    end
  end
end
