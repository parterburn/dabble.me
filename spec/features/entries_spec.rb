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

    it 'renders one blank line for every mixed Gmail paragraph separator' do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "First paragraph\n\nSecond paragraph\n\nThird paragraph. Lorem ipsum\n\nFourth paragraph. Lorem ipsum",
        vendor_specific: {
          stripped_html: '<div>First paragraph<br></div><div>Second paragraph</div><div><br></div><div>Third paragraph.&nbsp;Lorem ipsum</div><div><br></div><div>Fourth paragraph.&nbsp;Lorem ipsum</div>'
        }
      )

      EmailProcessor.new(email).process
      processed_entry = paid_user.entries.reload.first

      sign_in paid_user
      visit day_entry_url(year: processed_entry.date.year, month: processed_entry.date.month, day: processed_entry.date.day)

      rendered_entry = page.find('.s-scrollable')
      expect(rendered_entry.all(:xpath, './*').map(&:tag_name)).to eq(%w[div br div br div br div])
      expect(rendered_entry.text.split("\n")).to eq(
        [
          'First paragraph',
          'Second paragraph',
          'Third paragraph. Lorem ipsum',
          'Fourth paragraph. Lorem ipsum'
        ]
      )
    end

    it 'renders all authored paragraphs when Mailgun stripped HTML is truncated' do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "First paragraph\n\nSecond paragraph\n\nThird paragraph\n\nFourth paragraph",
        raw_html: '<div dir="ltr"><div>First paragraph<br><div class="gmail_quote"><div dir="ltr"><div><br></div><div>Second paragraph</div><div><br></div><div>Third paragraph</div><div><br></div><div>Fourth paragraph</div></div></div></div><div class="gmail_signature"><div><br>--<br></div><div>Sender signature</div></div></div>',
        vendor_specific: {
          stripped_html: '<div><div>First paragraph</div></div>'
        }
      )

      EmailProcessor.new(email).process
      processed_entry = paid_user.entries.reload.first

      expect(processed_entry.body).to eq(
        '<div>First paragraph<br><br>Second paragraph<br><br>Third paragraph<br><br>Fourth paragraph</div>'
      )

      sign_in paid_user
      visit day_entry_url(year: processed_entry.date.year, month: processed_entry.date.month, day: processed_entry.date.day)

      rendered_entry = page.find('.s-scrollable')
      rendered_body = rendered_entry.find(:xpath, './div')
      expect(rendered_body.all(:xpath, './br').map(&:tag_name)).to eq(%w[br br br br br br])
      expect(rendered_entry).to have_text('First paragraph')
      expect(rendered_entry).to have_text('Second paragraph')
      expect(rendered_entry).to have_text('Third paragraph')
      expect(rendered_entry).to have_text('Fourth paragraph')
      expect(rendered_entry).not_to have_text('Sender signature')
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

  describe 'edit' do
    it 'shows a clear delete link below the update button' do
      sign_in paid_user
      visit edit_entry_url(paid_entry)

      delete_link = page.find('form + .delete-entry-action a.s-delete', text: 'delete this entry')
      expect(delete_link['data-method']).to eq('delete')
      expect(delete_link['data-confirm']).to eq('Are you sure you want to delete this entry? There is no undo.')
      expect(page).not_to have_css('.s-entry-date .fa-trash')
    end
  end

end
