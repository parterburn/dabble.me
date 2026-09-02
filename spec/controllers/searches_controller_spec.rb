require 'rails_helper'

RSpec.describe SearchesController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    user
    entry
  end

  describe 'show' do
    it 'should redirect to login url if not logged in' do
      get :show
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should not allow search for a free user' do
      sign_in user
      get :show
      expect(response.status).to eq 200
      expect(response.body).to have_content('Subscribe Now')
      expect(response.body).to have_content('for $4/mo unlocks search and to see which tags are used most.')
      expect(response.body).to have_content("Pro users can use")
    end

    it 'should allow search for a paid user' do
      sign_in user
      user.plan = 'PRO Gumroad Monthly'
      user.save
      get :show
      expect(response.status).to eq 200
      expect(response.body).to have_content("Tip: Use")
      expect(response.body).to have_content("hashtags throughout your entries and you'll see a tag cloud appear here")
    end

    it 'shows matching entries, export, and an AI connector CTA for a paid user' do
      sign_in paid_user
      paid_entry.update!(body: 'Katelyn got so drunk she does not remember a thing.')

      get :show, params: { search: { term: 'a thing' } }

      expect(response.status).to eq 200
      expect(response.body).to have_content('remember a thing')
      expect(response.body).to have_content('Export Search Entries')
      expect(response.body).to have_link('How to use the AI Connector', href: mcp_server_docs_path)
      expect(response.body).not_to have_selector('code', text: 'AI connector')
      expect(response.body).not_to have_css('.email-address-box')
      expect(response.body).not_to have_css('.email-post-card a', text: 'Export Search Entries')
    end
  end
end
