require 'rails_helper'

RSpec.describe 'Privacy policy', type: :request do
  it 'says journal entries are encrypted in the database, with the keys kept separately, and that this is not end-to-end encryption' do
    get privacy_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Your journal entries are encrypted in the database, and the keys are kept separately from the database.')
    expect(response.body).to include('This is not end-to-end encryption.')
  end
end
