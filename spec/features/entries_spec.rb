require 'rails_helper'

describe 'Day Entries' do
  include_context 'has all objects'

  describe 'show' do
    it 'should redirect to sign in if not logged in' do
      visit day_entry_url(year: entry.date.year, month: entry.date.month, day: entry.date.day)
      expect(page).to have_content 'You need to login or sign up before continuing.'

      visit random_entry_url
      expect(page).to have_content 'You need to login or sign up before continuing.'
    end

    it 'should show an entry to logged in users' do
      sign_in user
      visit day_entry_url(year: entry.date.year, month: entry.date.month, day: entry.date.day)
      expect(page).to have_content entry.body

      visit random_entry_url
      expect(page).to have_content entry.body

      sign_out user
      visit day_entry_url(year: entry.date.year, month: entry.date.month, day: entry.date.day)
      expect(page).to have_content 'You need to login or sign up before continuing.'
    end

    it 'should not show me other users entries' do
      sign_in user
      visit day_entry_url(year: entry.date.year + 1, month: entry.date.month + 1, day: entry.date.day + 1)
      expect(page).to have_content 'Not authorized'
    end    
  end

end
