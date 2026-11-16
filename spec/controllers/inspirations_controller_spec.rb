require 'rails_helper'

RSpec.describe InspirationsController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    user
    superuser
    inspiration
  end

  describe 'index' do
    it 'should redirect to login url if not logged in' do
      get :index
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries path if not superuser' do
      sign_in user
      get :index
      expect(response.status).to eq 302
      expect(response).to redirect_to(entries_path)
    end

    it 'should show Inspirations to superusers' do
      sign_in_admin superuser
      get :index
      expect(response.status).to eq 200
      expect(response.body).to have_content('Add new inspiration')
    end

    it "counts each inspiration's entries, without asking once per inspiration" do
      used = Inspiration.create!(category: 'Question', body: 'What surprised you?')
      Inspiration.create!(category: 'Question', body: 'Never used')
      3.times { |n| FactoryBot.create(:entry, user: user, inspiration: used, date: n.days.ago) }
      sign_in_admin superuser

      counts = []
      listener = ->(*, payload) { counts << payload[:sql] if payload[:sql].match?(/COUNT\(\*\).*FROM "entries"/i) }
      ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') { get :index }

      rows = Nokogiri::HTML(response.body).css('tbody tr').to_h { |row| [row.css('td')[3].text.strip, row.css('td')[1].text.strip] }
      expect(rows).to include('What surprised you?' => '3', 'Never used' => '0')
      expect(counts.size).to eq(1)
    end
  end
end
