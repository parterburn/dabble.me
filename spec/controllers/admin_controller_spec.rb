require 'rails_helper'

RSpec.describe AdminController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    user
    superuser
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
      expect(response).to redirect_to(entries_path)
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
      expect(response).to redirect_to(entries_path)
    end

    it 'should show Admin Stats to superusers' do
      sign_in superuser
      get :stats
      expect(response.status).to eq 200
      expect(response.body).to have_content('Admin Stats')
      expect(response.body).to have_content('ARR')
      expect(response.body).to have_content('MRR')
      expect(response.body).to have_content('Pricing cohorts')
      expect(response.body).to have_content('PRO / Free')
      expect(response.body).to have_content('MCP')
      expect(response.body).to have_content('Connected now')
    end

    it 'does not call Mailgun while rendering the page' do
      expect(BusinessMetrics::MailgunStats).not_to receive(:fetch)
      sign_in superuser
      get :stats
      expect(response.status).to eq 200
    end
  end

  describe 'capture_stats' do
    before do
      allow(BusinessMetrics::MailgunStats).to receive(:fetch).and_return(
        BusinessMetrics::MailgunStats::Result.new(sent: 0, failed: 0, opened: 0, complained: 0)
      )
    end

    it 'redirects non-admins' do
      sign_in user
      post :capture_stats
      expect(response).to redirect_to(entries_path)
    end

    it 'snapshots metrics for superusers' do
      sign_in superuser
      expect { post :capture_stats }.to change(BusinessMetricSnapshot, :count).by(1)
      expect(BusinessMetricSnapshot.last.captured_on).to eq(Date.current)
      expect(response).to redirect_to(admin_stats_path)
    end
  end
end
