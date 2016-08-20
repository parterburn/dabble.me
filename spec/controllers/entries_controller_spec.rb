require 'rails_helper'

RSpec.describe EntriesController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    user
    entry
    not_my_entry
  end

  describe 'index' do
    it 'should redirect to sign in if not logged in' do
      get :index
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should show entries' do
      sign_in user
      get :index
      expect(response.status).to eq 200
      expect(response.body).to have_content(entry.body)
      expect(response.body).to_not have_content(not_my_entry.body)
    end
  end

  describe 'edit' do
    it 'should redirect to sign in if not logged in' do
      get :edit, id: entry.id
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should edit entry' do
      sign_in user
      get :edit, id: entry.id
      expect(response.status).to eq 200
      expect(response.body).to have_content(entry.body)
    end
  end

  describe 'new' do
    it 'should redirect to sign in if not logged in' do
      get :new
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should let me create an entry' do
      sign_in user
      get :new
      expect(response.status).to eq 200
      expect(response.body).to have_content('NEW ENTRY')
    end
  end

  describe 'create' do
    let(:params) do
      { entry: {
        entry: 'Testing body',
        date: Time.now,
        image_url: 'https://dabble.me/favicon-32x32.png',
        inspiration_id: inspiration.id } }
    end

    it 'should redirect to sign in if not logged in' do
      post :create, params
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should not let me create an entry if free user' do
      sign_in user
      expect { post :create, params }.to_not change { Entry.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(root_path)
    end

    it 'should let me create an entry if paid user' do
      sign_in user
      user.plan = 'PRO Gumroad Monthly'
      user.save
      expect { post :create, params }.to change { Entry.count }.by(1)
      expect(response.status).to eq 302
      expect(response).to redirect_to(day_entry_url(year: Entry.last.date.year, month: Entry.last.date.month, day: Entry.last.date.day))
    end    
  end

  describe 'destroy' do
    it 'should redirect to sign in if not logged in' do
      delete :destroy, id: entry.id
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it "should not delete entries unless user is pro" do
      sign_in user
      expect { delete :destroy, id: not_my_entry.id }.to_not change { Entry.count }
    end

    it 'should delete pro user entries' do
      sign_in user
      user.plan = 'PRO Gumroad Monthly'
      user.save      
      expect { delete :destroy, id: entry.id }.to change { Entry.count }.by(-1)
    end    

    it "should not delete entries that are not the user's" do
      sign_in user
      expect { delete :destroy, id: not_my_entry.id }.to_not change { Entry.count }
    end
  end

  describe 'calendar' do
    it 'should redirect to sign in if not logged in' do
      get :calendar
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should show me the page' do
      sign_in user
      get :calendar
      expect(response.status).to eq 200
      expect(response.body).to have_content('Calendar View')
    end
  end

  describe 'latest' do
    it 'should redirect to sign in if not logged in' do
      get :latest
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should show the latest entry' do
      sign_in user
      get :latest
      expect(response.status).to eq 200
      expect(response.body).to have_content(entry.body)
      expect(response.body).to_not have_content(not_my_entry.body)
    end

    it 'should show a CTA to logged in users without entries' do
      sign_in user
      user.plan = 'PRO Gumroad Monthly'
      user.save      
      expect { delete :destroy, id: entry.id }.to change { Entry.count }.by(-1)
      get :latest
      expect(response.status).to eq 200
      expect(response.body).to have_content("Reply to the email from Dabble Me and you'll see it here.")
    end
  end

  describe 'export' do
    it 'should redirect to sign in if not logged in' do
      get :export, format: 'txt'
      expect(response.status).to eq 401
      expect(response.body).to eq 'You need to login or sign up before continuing.'
    end

    it 'should show me the page' do
      sign_in user
      get :export, format: 'txt'
      expect(response.status).to eq 200
      expect(response.body).to have_content(entry.body)
      expect(response.body).to_not have_content(not_my_entry.body)
    end
  end
end
