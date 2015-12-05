require 'rails_helper'

RSpec.describe AdminController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    user
    superuser
  end

  describe 'metrics' do
    it 'should redirect to root url if not logged in' do
      get :metrics
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries if not superuser' do
      sign_in user
      get :metrics
      expect(response.status).to eq 302
      expect(response).to redirect_to(past_entries_path)
    end

    it 'should show Admin Metrics to superusers' do
      sign_in superuser
      get :metrics
      expect(response.status).to eq 200
      expect(response.body).to have_content('Admin Metrics')
    end
  end

  describe 'users' do
    it 'should redirect to root url if not logged in' do
      get :users
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries if not superuser' do
      sign_in user
      get :users
      expect(response.status).to eq 302
      expect(response).to redirect_to(past_entries_path)
    end

    it 'should show Admin Users to superusers' do
      sign_in superuser
      get :users
      expect(response.status).to eq 200
      expect(response.body).to have_content('Admin Users')
    end
  end

  describe 'stats' do
    it 'should redirect to root url if not logged in' do
      get :stats
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries if not superuser' do
      sign_in user
      get :stats
      expect(response.status).to eq 302
      expect(response).to redirect_to(past_entries_path)
    end

    it 'should show Admin Stats to superusers' do
      sign_in superuser
      get :stats
      expect(response.status).to eq 200
      expect(response.body).to have_content('Admin Stats')
    end
  end    
end
