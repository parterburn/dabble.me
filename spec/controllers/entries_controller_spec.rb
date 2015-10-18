require 'rails_helper'

RSpec.describe EntriesController, type: :controller do
  let(:user) do
    User.create(email: 'test@dabble.me', password: 'password')
  end

  let(:inspiration) do
    Inspiration.create(category: 'Email', body: 'Test Inspiration')
  end

  let(:entry) do
    user.entries.create(
      date: Time.now,
      body: 'Test body for an entry that is mine',
      image_url: 'https://dabble.me/favicon-32x32.png',
      inspiration_id: inspiration.id)
  end

  let(:not_my_entry) do
    Entry.create(
      date: Time.now,
      body: "Test body for an entry that isn't mine",
      image_url: 'https://dabble.me/favicon-32x32.png',
      inspiration_id: inspiration.id)
  end

  # Save objects to DB
  before :each do
    user
    entry
    not_my_entry
  end

  describe 'show' do
    it 'should redirect to sign in if not logged in' do
      get :show, id: entry.id
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)

      get :random
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should show entries to logged in users' do
      sign_in user
      get :show, id: entry.id
      expect(response.status).to eq 200
      expect(response.body).to have_content(entry.body)

      get :random
      expect(response.status).to eq 200
      expect(response.body).to have_content(entry.body)

      sign_out user
      get :show, id: entry.id
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should not show me other users entries' do
      sign_in user
      get :show, id: not_my_entry.id
      expect(response.status).to eq 302
      expect(response).to redirect_to(past_entries_url)
    end
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
      expect(response.body).to have_content('New Entry')
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

    it 'should let me create an entry' do
      sign_in user
      expect { post :create, params }.to change { Entry.count }.by(1)
      expect(response.status).to eq 302
      expect(response).to redirect_to(group_entries_url(group: Entry.last.date.year, subgroup: Entry.last.date.month))
    end
  end

  describe 'destroy' do
    it 'should redirect to sign in if not logged in' do
      delete :destroy, id: entry.id
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should delete user entries' do
      sign_in user
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

  describe 'export' do
    it 'should redirect to sign in if not logged in' do
      get :export, format: 'txt'
      expect(response.status).to eq 401
      expect(response.body).to eq 'You need to sign in or sign up before continuing.'
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
