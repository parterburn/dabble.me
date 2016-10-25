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

    it 'should allow search for a paid user' do
      sign_in user
      get :show
      expect(response.status).to eq 200
      expect(response.body).to have_content('Subscribe to PRO to use search.')
    end

    it 'should allow search for a paid user' do
      sign_in user
      user.plan = 'PRO Gumroad Monthly'
      user.save
      get :show
      expect(response.status).to eq 200
      expect(response.body).to have_content("Use hashtags throughout your entries and you'll see a tag cloud appear here")
    end
  end
end
