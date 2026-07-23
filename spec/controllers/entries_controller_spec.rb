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
      expect(response.body).to have_content(entry.formatted_body)
      expect(response.body).not_to have_content(not_my_entry.formatted_body)
    end

    it 'should clamp per page to a sane maximum' do
      sign_in user
      get :index, params: { per: 500 }
      expect(response.status).to eq 200
      expect(controller.send(:index_per_page)).to eq 50
    end
  end

  describe 'show' do
    before { sign_in user }

    it 'shows an entry stored at a non-midnight datetime for that calendar day' do
      entry.update_columns(date: Time.utc(2026, 7, 17, 15, 30, 0), body: '<p>UniqueShowBody999</p>')

      get :show, params: { year: 2026, month: 7, day: 17 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('UniqueShowBody999')
      expect(flash[:alert]).to be_blank
    end

    it 'shows a timezone beginning-of-day entry for that calendar day' do
      tz = ActiveSupport::TimeZone[user.send_timezone]
      day = Date.new(2026, 7, 17)
      entry.update_columns(
        date: tz.local(day.year, day.month, day.day).beginning_of_day,
        body: '<p>McpStyleShowBody</p>'
      )

      get :show, params: { year: 2026, month: 7, day: 17 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('McpStyleShowBody')
    end

    it 'redirects with Entry not found when no entry exists that day' do
      get :show, params: { year: 2099, month: 1, day: 1 }

      expect(response).to redirect_to(entries_path)
      expect(flash[:alert]).to eq('Entry not found.')
    end
  end

  describe 'edit' do
    it 'should redirect to sign in if not logged in' do
      get :edit, params: { id: entry.id }
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should edit entry' do
      sign_in user
      get :edit, params: { id: entry.id }
      expect(response.status).to eq 200
      expect(response.body).to have_content(entry.formatted_body)
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
      expect { post :create, params: params }.not_to change { Entry.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should not let me create an entry if free user' do
      sign_in user
      expect { post :create, params: params }.not_to change { Entry.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(root_path)
    end

    it 'should let me create an entry if paid user' do
      sign_in user
      user.plan = 'PRO PayHere Monthly'
      user.save
      params[:entry][:date] = Date.new(2027, 3, 15)
      expect { post :create, params: params }.to change { Entry.count }.by(1)
      expect(response.status).to eq 302
      expect(response).to redirect_to(day_entry_url(year: 2027, month: 3, day: 15))
    end

    it 'should merge into an existing same-day entry if paid user' do
      sign_in paid_user
      existing = paid_user.entries.create!(date: Time.utc(2026, 8, 1, 15, 0, 0), body: '<p>Morning</p>')
      merge_params = {
        entry: {
          entry: 'Afternoon addition',
          date: Time.utc(2026, 8, 1, 9, 0, 0),
          inspiration_id: inspiration.id
        }
      }

      expect { post :create, params: merge_params }.not_to change { Entry.count }
      expect(response).to redirect_to(day_entry_url(year: 2026, month: 8, day: 1))
      expect(existing.reload.body).to include('Morning')
      expect(existing.body).to include('Afternoon addition')
    end
  end

  describe 'destroy' do
    it 'should redirect to sign in if not logged in' do
      delete :destroy, params: { id: entry.id }
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it "should not delete entries unless user is pro" do
      sign_in user
      expect { delete :destroy, params: { id: not_my_entry.id } }.not_to change { Entry.count }
    end

    it 'should delete pro user entries' do
      sign_in user
      user.plan = 'PRO PayHere Monthly'
      user.save
      expect { delete :destroy, params: { id: entry.id } }.to change { Entry.count }.by(-1)
    end

    it "should not delete entries that are not the user's" do
      sign_in user
      expect { delete :destroy, params: { id: not_my_entry.id } }.not_to change { Entry.count }
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
      expect(response.body).to have_content(entry.formatted_body)
      expect(response.body).not_to have_content(not_my_entry.formatted_body)
    end

    it 'should show a CTA to logged in users without entries' do
      sign_in user
      user.plan = 'PRO PayHere Monthly'
      user.save
      expect { delete :destroy, params: { id: entry.id } }.to change { Entry.count }.by(-1)
      get :latest
      expect(response.status).to eq 200
      expect(response.body).to have_content("reply to the email from Dabble Me to create your first entry")
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
      expect(response.body).to have_content(entry.formatted_body)
      expect(response.body).not_to have_content(not_my_entry.formatted_body)
    end
  end
end
