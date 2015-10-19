require 'rails_helper'

RSpec.describe RegistrationsController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    request.env['devise.mapping'] = Devise.mappings[:user]
    user
  end

  describe 'edit' do
    it 'should redirect to root url if not logged in' do
      get :edit
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should show edit screen if signed in' do
      sign_in user
      get :edit
      expect(response.status).to eq 200
      expect(response.body).to have_content("#{user.user_key}@#{ENV['SMTP_DOMAIN']}")
    end

    it 'should let user edit if visiting /settings/user_key without signing in' do
      get :settings, user_key: user.user_key
      expect(response.status).to eq 200
      expect(response.body.should have_css('input[type=checkbox][disabled]', count: 6))
    end

    it 'should let paid user edit all settings' do
      get :settings, user_key: paid_user.user_key
      expect(response.status).to eq 200
      expect(response.body.should have_css('input[type=checkbox][disabled]', count: 0))
    end

    it 'should let user easily unsubscribe' do
      post :unsubscribe, { user_key: user.user_key, unsub_all: 'yes', user: { email: user.email } }
      expect(response.status).to eq 302
      expect(response).to redirect_to(settings_url(user.user_key))
      expect(user.reload.frequency.count).to eq 0
    end
  end

  describe 'update' do
    let(:params) do
      {
        frequency: { 'Sun'=>'1', 'Mon'=>'1', 'Tue'=>'1' },
        user: {
          first_name: 'Testy',
          last_name: "O'tester",
          send_time: '11:00:00',
          send_timezone: 'Alaska',
          send_past_entry: '0',
          email: user.email,
          password: '',
          password_confirmation: '',
          current_password: ''
        }
      }
    end

    it 'should redirect to root url if not logged in' do
      post :update, params
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should allow user updates to basic info' do
      sign_in user
      expect(user.frequency.count).to eq 1
      post :update, params
      expect(response.status).to eq 302
      expect(response).to redirect_to(edit_user_registration_url)
      expect(user.reload.frequency.count).to eq 3
      expect(user.full_name).to eq "Testy O'tester"
      expect(user.send_timezone).to eq 'Alaska'
      expect(user.send_time).to eq '2000-01-01 11:00:00.000000000 +0000'
      expect(user.send_past_entry).to eq false
    end

    it 'should not allow user updates to non-basic info with incorrect password' do
      sign_in user
      old_email = user.email
      old_full_name = user.full_name
      expect(user.frequency.count).to eq 1
      post :update, params.deep_merge(user: { email: Faker::Internet.email, current_password: 'wrong' })
      expect(response.status).to eq 302
      expect(response).to redirect_to(edit_user_registration_url)
      expect(user.reload.frequency.count).to eq 1
      expect(user.email).to eq old_email
      expect(user.full_name).to eq old_full_name
    end

    it 'should allow user updates to non-basic info with correct password' do
      sign_in user
      expect(user.frequency.count).to eq 1
      old_password = user.encrypted_password
      email = Faker::Internet.email
      post :update, params.deep_merge(user: { email: email, password: 'blueblue', password_confirmation: 'blueblue', current_password: user.password })
      expect(response.status).to eq 302
      expect(response).to redirect_to(edit_user_registration_url)
      expect(user.reload.frequency.count).to eq 3
      expect(user.email).to eq email
      expect(user.full_name).to eq "Testy O'tester"
      expect(user.encrypted_password).to_not eq old_password
    end
  end

  describe 'creating a user' do
    it 'should see create user form' do
      get :new
      expect(response.body).to have_field('user_email')
      expect(response.body).to have_field('user_password')
      expect(response.body).to have_field('user_password_confirmation')
      expect(response.status).to eq 200
    end

    it 'should be able to create free user and send that user an email' do
      email = Faker::Internet.email
      new_password = Faker::Internet.password(8)
      post :create, { user: { email: email, password: new_password, password_confirmation: new_password } }
      expect(response.status).to eq 302
      expect(response).to redirect_to(root_url)

      new_free_user = User.last

      expect(ActionMailer::Base.deliveries.last.to).to eq [email]
      expect(ActionMailer::Base.deliveries.last.subject).to eq "Let's write your first Dabble Me entry"

      new_entry_email_body = Faker::Lorem.paragraph

      # Check that EmailProcessor will take email and create an entry for it
      params = { to: [{
                    full: "#{new_free_user.user_key}@#{ENV['SMTP_DOMAIN']}",
                    email: "#{new_free_user.user_key}@#{ENV['SMTP_DOMAIN']}",
                    token: "#{new_free_user.user_key}",
                    host: "#{ENV['SMTP_DOMAIN']}",
                    name: nil
                  }],
                  body: new_entry_email_body }

      email = FactoryGirl.build(:email, params)
      expect{ EmailProcessor.new(email).process }.to change{ new_free_user.entries.count }.by(1)
      expect(new_free_user.entries.last.body).to eq "#{new_entry_email_body} "
      expect(new_free_user.entries.last.date.strftime('%Y-%m-%d')).to eq DateTime.now.in_time_zone(new_free_user.send_timezone).strftime('%Y-%m-%d')

      # Check that sending two emails on the same day merge into 1 Entry
      expect{ EmailProcessor.new(email).process }.to change{ new_free_user.entries.count }.by(0)
      expect(new_free_user.entries.last.body).to eq "#{new_entry_email_body} #{new_entry_email_body} "
      expect(new_free_user.entries.last.date.strftime('%Y-%m-%d')).to eq DateTime.now.in_time_zone(new_free_user.send_timezone).strftime('%Y-%m-%d')
    end

    it 'should be able to create paid user and send that user an email with formatting' do
      email = Faker::Internet.email
      new_password = Faker::Internet.password(8)
      post :create, { user: { email: email, password: new_password, password_confirmation: new_password } }
      new_paid_user = User.last
      new_paid_user.plan = 'PRO Monthly Gumroad'
      new_paid_user.save
      expect(ActionMailer::Base.deliveries.last.to).to eq [email]
      expect(ActionMailer::Base.deliveries.last.subject).to eq "Let's write your first Dabble Me entry"

      new_entry_email_body = Faker::Lorem.paragraph

      # Check that EmailProcessor will take email and create an entry for it
      params = { to: [{
                    full: "#{new_paid_user.user_key}@#{ENV['SMTP_DOMAIN']}",
                    email: "#{new_paid_user.user_key}@#{ENV['SMTP_DOMAIN']}",
                    token: "#{new_paid_user.user_key}",
                    host: "#{ENV['SMTP_DOMAIN']}",
                    name: nil
                  }],
                  body: new_entry_email_body }

      email = FactoryGirl.build(:email, params)
      expect{ EmailProcessor.new(email).process }.to change{ new_paid_user.entries.count }.by(1)
      expect(new_paid_user.entries.last.body).to eq "<p>#{new_entry_email_body} </p>"
      expect(new_paid_user.entries.last.date.strftime('%Y-%m-%d')).to eq DateTime.now.in_time_zone(new_paid_user.send_timezone).strftime('%Y-%m-%d')

      # Check that sending two emails on the same day merge into 1 Entry
      expect{ EmailProcessor.new(email).process }.to change{ new_paid_user.entries.count }.by(0)
      expect(new_paid_user.entries.last.body).to eq "<p>#{new_entry_email_body} </p><hr><p>#{new_entry_email_body} </p>"
      expect(new_paid_user.entries.last.date.strftime('%Y-%m-%d')).to eq DateTime.now.in_time_zone(new_paid_user.send_timezone).strftime('%Y-%m-%d')
    end    
  end
end
