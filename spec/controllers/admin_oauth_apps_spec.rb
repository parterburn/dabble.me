require 'rails_helper'

RSpec.describe AdminController, type: :controller do
  let(:admin) { create(:user, admin: true) }
  let(:alice) { create(:user, email: 'alice@example.com') }
  let(:bob) { create(:user, email: 'bob@example.com') }

  def register(name, redirect_uri, created_at: 1.day.ago)
    Doorkeeper::Application.create!(name: name, redirect_uri: redirect_uri, scopes: 'mcp:access',
                                    confidential: false, created_at: created_at)
  end

  def token(application, user, created_at: 1.hour.ago, revoked_at: nil)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id, scopes: 'mcp:access',
                                    expires_in: 1.day.to_i, created_at: created_at, revoked_at: revoked_at)
  end

  let!(:claude_old) { register('Claude', 'https://claude.ai/api/mcp/auth_callback', created_at: 20.days.ago) }
  let!(:claude_new) { register('Claude', 'https://claude.ai/api/mcp/auth_callback', created_at: 2.days.ago) }
  let!(:probe) { register('t', 'https://evil.example/cb', created_at: 3.days.ago) }

  before do
    token(claude_new, alice)
    token(claude_old, bob, revoked_at: 1.day.ago)
    McpToolInvocation.create!(user: alice, tool_name: 'list_entries', oauth_application_id: claude_new.id, created_at: 2.hours.ago)
  end

  describe 'oauth_apps' do
    it 'redirects a non-admin' do
      sign_in alice
      get :oauth_apps
      expect(response).to redirect_to(entries_path)
    end

    it 'groups registrations by name with who is connected' do
      sign_in_admin admin
      get :oauth_apps

      expect(response).to have_http_status(:ok)
      page = Capybara.string(response.body)
      claude_row = page.find('tr', text: 'Claude')
      expect(claude_row).to have_css('td', text: /\A2\z/) # registrations
      expect(claude_row).to have_css('td', text: 'claude.ai')
      expect(page.find('tr', text: 'evil.example')).to have_link('t')
      expect(page).not_to have_css('h2', text: /\ARegistrations\z/)
      expect(page).not_to have_button('Delete')
    end

    it "lists each registration and its users when filtered by name" do
      sign_in_admin admin
      get :oauth_apps, params: { name: 'Claude' }

      page = Capybara.string(response.body)
      expect(page).to have_css('h2', text: 'Registrations')
      expect(page).to have_link('alice@example.com', href: edit_admin_user_path(alice))
      expect(page).not_to have_link('bob@example.com') # revoked
      expect(page).to have_button('Delete', count: 2)
      expect(page).not_to have_content('evil.example')
    end

    it "keeps only the apps a user has connected when filtered by email" do
      sign_in_admin admin
      get :oauth_apps, params: { email: 'bob@' }

      page = Capybara.string(response.body)
      expect(page).to have_content('Claude')
      expect(page).not_to have_content('evil.example')
    end

    it "doesn't offer to delete the iOS app" do
      MobileApp.ensure_application!
      sign_in_admin admin
      get :oauth_apps, params: { name: MobileApp::NAME }

      page = Capybara.string(response.body)
      expect(page).to have_content('iOS app')
      expect(page).not_to have_button('Delete')
    end

    it 'treats the name filter as text, not a pattern' do
      sign_in_admin admin
      get :oauth_apps, params: { name: '%' }
      expect(Capybara.string(response.body)).to have_content('No apps match.')
    end
  end

  describe 'destroy_oauth_app' do
    it 'deletes the registration and disconnects its users' do
      sign_in_admin admin
      delete :destroy_oauth_app, params: { application_id: claude_new.id, name: 'Claude' }

      expect(response).to redirect_to(admin_oauth_apps_path(name: 'Claude'))
      expect(flash[:notice]).to include('1 user disconnected')
      expect(Doorkeeper::Application.exists?(claude_new.id)).to be(false)
      expect(Doorkeeper::AccessToken.where(application_id: claude_new.id)).to be_empty
    end

    it "refuses to delete the iOS app's client" do
      mobile = MobileApp.ensure_application!
      sign_in_admin admin
      delete :destroy_oauth_app, params: { application_id: mobile.id }

      expect(flash[:alert]).to include("can't be deleted")
      expect(Doorkeeper::Application.exists?(mobile.id)).to be(true)
    end

    it 'redirects a non-admin' do
      sign_in alice
      delete :destroy_oauth_app, params: { application_id: probe.id }
      expect(response).to redirect_to(entries_path)
      expect(Doorkeeper::Application.exists?(probe.id)).to be(true)
    end
  end

  describe 'edit_user' do
    it "shows the user's connected and revoked apps" do
      token(probe, alice, revoked_at: 1.hour.ago)
      sign_in_admin admin
      get :edit_user, params: { id: alice.id }

      section = Capybara.string(response.body).find('#connected-apps')
      expect(section.find('tr', text: 'Claude')).to have_content('Connected')
      expect(section.find('tr', text: 'evil.example')).to have_content('Revoked')
    end

    it 'says so when the user has no apps' do
      sign_in_admin admin
      get :edit_user, params: { id: admin.id }
      expect(Capybara.string(response.body).find('#connected-apps')).to have_content('None.')
    end
  end
end
