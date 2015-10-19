require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    user
    superuser
  end

  describe 'admin' do
    it 'should redirect to root url if not logged in' do
      get :admin
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries if not superuser' do
      sign_in user
      get :admin
      expect(response.status).to eq 302
      expect(response).to redirect_to(past_entries_path)
    end

    it 'should show Admin Dashboard to superusers' do
      sign_in superuser
      get :admin
      expect(response.status).to eq 200
      expect(response.body).to have_content('All Users')
    end
  end
end
