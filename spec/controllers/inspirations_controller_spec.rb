require 'rails_helper'

RSpec.describe InspirationsController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    user
    superuser
    inspiration
  end

  describe 'index' do
    it 'should redirect to login url if not logged in' do
      get :index
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries path if not superuser' do
      sign_in user
      get :index
      expect(response.status).to eq 302
      expect(response).to redirect_to(entries_path)
    end

    it 'should show Inspirations to superusers' do
      sign_in superuser
      get :index
      expect(response.status).to eq 200
      expect(response.body).to have_content('Add new inspiration')
    end
  end
end
