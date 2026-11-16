require 'rails_helper'

# What changes for visitors and writers once an admin announces a closing
# (SiteClosure, set at /admin/closing).
RSpec.describe 'Closing Dabble Me', type: :request do
  let(:user) { FactoryBot.create(:user, plan: 'PRO Monthly PayHere') }
  let(:admin) { FactoryBot.create(:user, admin: true) }
  let(:signup) { { user: { email: 'new@example.com', password: 'a long password', first_name: 'New' } } }

  def long_date(day)
    day.strftime('%B %-d, %Y')
  end

  context 'while open' do
    it 'has no goodbye page or banner, and takes new accounts' do
      get goodbye_path
      expect(response).to redirect_to(root_path)

      get root_path
      expect(response.body).not_to include('Dabble Me is closing')

      get new_user_registration_path
      expect(response).to have_http_status(:ok)
    end
  end

  context 'once a closing is announced' do
    let(:closes_on) { Date.current + 30 }

    before { SiteClosure.announce(closes_on: closes_on, announced_by: admin) }

    it 'turns away new accounts' do
      get new_user_registration_path
      expect(response).to redirect_to(goodbye_path)

      expect { post user_registration_path, params: signup }.not_to change(User, :count)
      expect(response).to redirect_to(goodbye_path)
    end

    it 'turns away new subscriptions without calling Stripe' do
      expect(Stripe::Checkout::Session).not_to receive(:create)

      get '/subscribe'
      expect(response).to redirect_to(goodbye_path)

      sign_in user
      post checkout_path, params: { plan: 'yearly' }
      expect(response).to redirect_to(goodbye_path)
    end

    it 'puts the date on the public pages and explains it on the goodbye page' do
      get root_path
      expect(response.body).to include("Dabble Me is closing on #{long_date(closes_on)}", goodbye_path)

      get goodbye_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Dabble Me is closing', "will close on #{long_date(closes_on)}",
                                       "until #{long_date(closes_on + 30)}", export_entries_path)
    end

    it 'leaves the journal working, with the date and a link to export above it' do
      sign_in user
      get new_entry_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dabble Me is closing on #{long_date(closes_on)}", 'Export your journal')
    end
  end

  context 'from the closing date' do
    let(:closes_on) { Date.current }

    before { SiteClosure.announce(closes_on: closes_on, announced_by: admin) }

    it 'replaces the public site with the goodbye page, keeping the terms and privacy policy' do
      [root_path, '/support', '/journal-app'].each do |path|
        get path
        expect(response).to redirect_to(goodbye_path)
      end

      get goodbye_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Dabble Me has closed', "closed on #{long_date(closes_on)}", "until #{long_date(closes_on + 30)}")

      ['/privacy', '/terms'].each do |path|
        get path
        expect(response).to have_http_status(:ok)
      end
    end

    it 'replaces the journal with the goodbye page and takes no new entries on the web' do
      sign_in user

      [entries_path, '/today', '/search', new_entry_path].each do |path|
        get path
        expect(response).to redirect_to(goodbye_path)
      end

      expect { post entries_path, params: { entry: { entry: 'One more', date: Date.current.to_s } } }.not_to change(Entry, :count)
      expect(response).to redirect_to(goodbye_path)
    end

    it 'still lets people sign in, export and reach their settings' do
      get new_user_session_path
      expect(response).to have_http_status(:ok)

      sign_in user
      get export_entries_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dabble Me closed on #{long_date(closes_on)}")

      get edit_user_registration_path
      expect(response).to have_http_status(:ok)
    end

    it 'still shows an admin the journal' do
      allow(AdminAccess).to receive(:passkey_fresh?).and_return(true)
      sign_in admin

      get new_entry_path
      expect(response).to have_http_status(:ok)
    end

    it 'opens again when the closing is called off' do
      SiteClosure.reopen!

      get root_path
      expect(response).to have_http_status(:ok)
      get new_user_registration_path
      expect(response).to have_http_status(:ok)
    end
  end
end
