require 'rails_helper'

# Sign-up asks for no name: the email is the account. A first name is optional, in Settings.
RSpec.describe 'Signing up without a name', type: :request do
  let(:password) { 'a long password' }

  it 'shows no name fields on the sign-up form' do
    get new_user_registration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('user[first_name]')
    expect(response.body).not_to include('user[last_name]')
    expect(response.body).to include('user[email]')
  end

  it 'creates the account without storing a name, even if one is posted' do
    expect do
      post user_registration_path, params: {
        user: { email: 'nameless@example.com', password: password, password_confirmation: password,
                first_name: 'Ada', last_name: 'Lovelace' }
      }
    end.to change(User, :count).by(1)

    user = User.find_by(email: 'nameless@example.com')
    expect(user.first_name).to be_nil
    expect(user.last_name).to be_nil
    expect(user.first_name_or_fallback).to eq('there')
  end

  describe 'the Settings page' do
    it 'offers an optional first name and no last name to someone without one' do
      user = FactoryBot.create(:user, first_name: nil, last_name: nil)
      sign_in user

      get edit_user_registration_path

      expect(response.body).to include('What should we call you? (optional)')
      expect(response.body).to include('user[first_name]')
      expect(response.body).not_to include('user[last_name]')
    end

    it 'still shows an existing last name, so it can be cleared' do
      user = FactoryBot.create(:user, first_name: 'Ada', last_name: 'Lovelace')
      sign_in user

      get edit_user_registration_path

      expect(response.body).to include('user[last_name]')
    end
  end

  describe 'names on the account' do
    it 'stores a cleared name as nil and builds full names without stray spaces' do
      user = FactoryBot.create(:user, first_name: 'Ada', last_name: 'Lovelace')

      user.update!(first_name: '  ', last_name: '')
      expect(user.reload.first_name).to be_nil
      expect(user.last_name).to be_nil
      expect(user.full_name).to be_nil
      expect(user.cleaned_to_address).to eq(user.email)

      user.update!(first_name: ' Ada ')
      expect(user.reload.first_name).to eq('Ada')
      expect(user.full_name).to eq('Ada')
      expect(user.full_name_or_email).to eq('Ada')
      expect(user.cleaned_to_address).to eq("Ada <#{user.email}>")
    end

    it "can't be changed from an email settings link" do
      user = FactoryBot.create(:user, first_name: 'Ada', last_name: 'Lovelace')

      put unsubscribe_path(token: user.email_settings_token), params: { user: { first_name: 'Mallory', last_name: 'X' } }

      expect(user.reload.first_name).to eq('Ada')
      expect(user.last_name).to eq('Lovelace')
    end
  end
end
