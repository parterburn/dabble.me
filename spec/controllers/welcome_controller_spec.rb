require 'rails_helper'

RSpec.describe WelcomeController, type: :controller do
  include_context 'has all objects'

  describe 'index' do
    it 'should show the welcome page to non-logged in users' do
      get :index
      expect(response.status).to eq 200
      expect(response.body).to have_content("Dabble Me helps you remember what's happened in your life.")
    end

    it 'should show a CTA to logged in users without entries' do
      sign_in user
      get :index
      expect(response.status).to eq 200
      expect(response.body).to have_content("Check your email - simply reply to that email and you'll see it here.")
    end

    it 'should redirect to latest entry for logged in users' do
      entry
      not_my_entry
      sign_in user
      get :index
      expect(response.status).to eq 302
      expect(response).to redirect_to(latest_entry_url)
    end
  end
end
