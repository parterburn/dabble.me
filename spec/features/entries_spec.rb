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
      expect(page).to have_current_path(day_entry_path(year: entry.date.year, month: entry.date.month, day: entry.date.day))
      expect(page).to have_content entry.formatted_body
      expect(page).not_to have_content 'Not authorized'
      expect(page).not_to have_content 'Entry not found'

      visit random_entry_url
      expect(page).to have_content entry.formatted_body

      sign_out user
      visit day_entry_url(year: entry.date.year, month: entry.date.month, day: entry.date.day)
      expect(page).to have_content 'You need to login or sign up before continuing.'
    end

    it 'should show an entry stored at a non-midnight datetime' do
      sign_in user
      entry.update_columns(date: Time.utc(2026, 7, 17, 15, 30, 0), body: '<p>Afternoon journal entry</p>')

      visit day_entry_url(year: 2026, month: 7, day: 17)
      expect(page).to have_current_path(day_entry_path(year: 2026, month: 7, day: 17))
      expect(page).to have_content 'Afternoon journal entry'
      expect(page).not_to have_content 'Not authorized'
    end

    it 'should show a timezone-midnight entry (e.g. MCP-created)' do
      sign_in user
      tz = ActiveSupport::TimeZone[user.send_timezone]
      day = Date.new(2026, 7, 17)
      entry.update_columns(
        date: tz.local(day.year, day.month, day.day).beginning_of_day,
        body: '<p>Timezone day start entry</p>'
      )

      visit day_entry_url(year: 2026, month: 7, day: 17)
      expect(page).to have_content 'Timezone day start entry'
      expect(page).not_to have_content 'Not authorized'
    end

    it 'should say entry not found for a day without an entry' do
      sign_in user
      visit day_entry_url(year: entry.date.year + 1, month: entry.date.month, day: entry.date.day)
      expect(page).to have_content 'Entry not found'
      expect(page).not_to have_content 'Not authorized'
    end

    it 'should not show me other users entries' do
      sign_in user
      visit group_entries_url(group: not_my_entry.id)
      expect(page).not_to have_content not_my_entry.body
    end

    it 'should not show me other users entries in edit mode' do
      sign_in user
      visit edit_entry_url(not_my_entry)
      expect(page).to have_content 'Entry not found'
    end

    it 'should show me the calendar with my entries', js: true do
      sign_in paid_user
      entry.update(date: Date.today, image: nil)

      visit entries_calendar_path
      expect(page).to have_content ActionController::Base.helpers.strip_tags(paid_entry.sanitized_body&.gsub(/\n/, '') )&.truncate(50, separator: ' ')
    end
  end

end
