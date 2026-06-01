require 'rails_helper'

RSpec.describe SessionsController, type: :controller do
  include_context 'has all objects'

  before do
    request.env['devise.mapping'] = Devise.mappings[:user]
  end

  describe 'create' do
    it 'cancels pending deletion when the user signs in' do
      user.update_column(:deleted_at, Time.current)

      post :create, params: { user: { email: user.email, password: user.password } }

      expect(user.reload.deleted_at).to be_nil
      expect(flash[:notice]).to eq(I18n.t('devise.sessions.deletion_cancelled'))
    end
  end
end
