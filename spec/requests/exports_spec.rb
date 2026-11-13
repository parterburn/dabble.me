require 'rails_helper'

RSpec.describe 'Exports', type: :request do
  include_context 'with export storage'

  let(:user) { FactoryBot.create(:user, plan: 'PRO Monthly PayHere') }
  let(:other_user) { FactoryBot.create(:user) }
  let(:export) do
    user.exports.create!.tap do |export|
      path = Pathname(Dir.mktmpdir).join('export.zip')
      path.binwrite('zip bytes')
      key = ExportStore.new.upload(ExportStore.key_for(export), path.to_s)
      export.ready!(storage_key: key, byte_size: 9, entry_count: 12, image_count: 3, skipped_image_count: 0)
    end
  end

  describe 'opening the emailed link' do
    it 'asks for a sign-in first' do
      get export_path(export)
      expect(response).to redirect_to(new_user_session_path)

      get download_export_path(export)
      expect(response).to redirect_to(new_user_session_path)
      expect(export.reload.download_count).to eq(0)
    end

    it 'shows the export to its owner' do
      sign_in user
      get export_path(export)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('12 entries', '3 photos', 'Download')
    end

    it 'never shows or serves it to someone else' do
      sign_in other_user

      get export_path(export)
      expect(response).to redirect_to(export_entries_path)

      get download_export_path(export)
      expect(response).to redirect_to(export_entries_path)
      expect(export.reload.download_count).to eq(0)
    end
  end

  describe 'downloading' do
    before { sign_in user }

    it 'redirects to a storage link that lasts minutes, and records the download' do
      get download_export_path(export)

      location = response.headers['Location']
      expect(location).to start_with('https://').and include(export.storage_key, 'X-Amz-Expires=300')
      expect(location).to include("dabble-me-#{export.created_at.strftime('%Y-%m-%d')}.zip")
      expect(export.reload.download_count).to eq(1)
      expect(export.downloaded_at).to be_present
    end

    it 'refuses once the export has expired' do
      export.update_columns(expires_at: 1.minute.ago)
      get download_export_path(export)

      expect(response).to redirect_to(export_path(export))
      expect(export.reload.download_count).to eq(0)

      get export_path(export)
      expect(response.body).to include('This export has expired')
    end

    it 'says so while the export is still being prepared' do
      preparing = user.exports.create!
      get export_path(preparing)
      expect(response.body).to include('still being prepared')
    end
  end

  describe 'the Export page' do
    before { sign_in user }

    it 'offers every year with entries, newest first, under All, and starts nothing by being opened' do
      FactoryBot.create(:entry, user: user, body: 'now', date: Time.utc(2026, 3, 1, 12))
      FactoryBot.create(:entry, user: user, body: 'then', date: Time.utc(2021, 3, 1, 12))
      FactoryBot.create(:entry, body: 'someone else', date: Time.utc(2019, 3, 1, 12))

      expect { get export_entries_path }.not_to(change { Export.count })
      page = Nokogiri::HTML(response.body)

      expect(response).to have_http_status(:ok)
      expect(page.css('select#year option').map(&:text)).to eq(%w[All 2026 2021])
      expect(page.at_css('select#year option[selected]')).to be_nil
      expect(page.at_css("form[action='#{export_entries_path}'][method='post']")).to be_present
      expect(page.css('button[name="download"]').map { |button| button['value'] }).to eq(%w[zip markdown])
    end

    it 'opens with a year already chosen, or for a search' do
      FactoryBot.create(:entry, user: user, body: 'then', date: Time.utc(2021, 3, 1, 12))

      get export_entries_path(year: '2021')
      expect(Nokogiri::HTML(response.body).at_css('select#year option[selected]').text).to eq('2021')

      get export_entries_path(search: { term: 'coffee <b>' })
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('select#year')).to be_nil
      expect(page.at_css('input[name="search[term]"]')['value']).to eq('coffee <b>')
      expect(page.at_css('mark').text).to eq('coffee <b>')
    end

    it 'lists exports that are ready to download, and only this person\'s' do
      user.exports.create!(status: 'ready', scope: 'year:2021', storage_key: 'exports/y.zip', byte_size: 2048, expires_at: 6.days.from_now)
      user.exports.create!(status: 'expired')
      other_user.exports.create!(status: 'ready', scope: 'year:2019', storage_key: 'exports/o.zip', byte_size: 2048, expires_at: 6.days.from_now)

      get export_entries_path

      expect(response.body).to include('Ready to download', 'Entries from 2021')
      expect(response.body).not_to include('Entries from 2019')
    end

    it 'is linked from the account menu, with Import above it' do
      get export_entries_path
      labels = Nokogiri::HTML(response.body).css('.navbar .dropdown.hidden-xs .dropdown-menu a').map { |link| link.text.strip }

      expect(labels).to eq(['Settings', 'Account Security', 'Import Entries', 'Export Entries', 'Logout'])
    end

    it 'needs a sign-in' do
      sign_out user
      get export_entries_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'requesting an export' do
    before { sign_in user }

    it 'queues a ZIP and promises a link by email' do
      FactoryBot.create(:entry, user: user, body: 'one entry')

      expect { post export_entries_path, params: { download: 'zip', year: '' } }.to change { user.exports.count }.by(1)
      expect(response).to redirect_to(export_entries_path)
      expect(flash[:notice]).to include('email you a link')
      expect(user.exports.last.status).to eq('preparing')
      expect(user.exports.last.scope).to eq('all')
    end

    it 'streams the journal as Markdown right away, without creating an export' do
      FactoryBot.create(:entry, user: user, body: '<p>one <b>entry</b></p>', date: Time.utc(2026, 3, 1, 12))
      FactoryBot.create(:entry, user: user, body: '<p>an older one</p>', date: Time.utc(2021, 3, 1, 12))
      FactoryBot.create(:entry, body: 'someone else')

      expect { post export_entries_path, params: { download: 'markdown' } }.not_to(change { Export.count })
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/markdown')
      expect(response.headers['Content-Disposition']).to match(/attachment; filename="dabble-me-\d{4}-\d\d-\d\d\.md"/)
      expect(response.body).to eq("# Dabble Me journal\n\n## 2021-03-01 (Monday)\n\nan older one\n\n## 2026-03-01 (Sunday)\n\none **entry**\n\n")

      get export_entries_path(format: :md)
      expect(response.body).to start_with("# Dabble Me journal\n\n## 2021-03-01")
    end

    it 'streams one year or one search as Markdown, named and titled for it' do
      FactoryBot.create(:entry, user: user, body: '<p>coffee in 2026</p>', date: Time.utc(2026, 3, 1, 12))
      FactoryBot.create(:entry, user: user, body: '<p>tea in 2021</p>', date: Time.utc(2021, 3, 1, 12))

      get export_entries_path(year: '2021', format: :md)
      expect(response.body).to start_with("# Dabble Me journal\n\nEntries from 2021\n\n")
      expect(response.body).to include('tea in 2021')
      expect(response.body).not_to include('coffee in 2026')
      expect(response.headers['Content-Disposition']).to match(/filename="dabble-me-2021-\d{4}-\d\d-\d\d\.md"/)

      post export_entries_path, params: { download: 'markdown', search: { term: 'Coffee & Tea' } }
      expect(response.headers['Content-Disposition']).to match(/filename="dabble-me-search-coffee-tea-\d{4}-\d\d-\d\d\.md"/)

      get export_entries_path(search: { term: 'coffee' }, format: :md)
      expect(response.body).to start_with("# Dabble Me journal\n\nEntries matching “coffee”\n\n")
      expect(response.body).to include('coffee in 2026')
      expect(response.body).not_to include('tea in 2021')
    end

    it 'records a year or a search on the export, and returns to the page for it' do
      expect { post export_entries_path, params: { year: '2021' } }.to have_enqueued_job(ExportEntriesJob).with(kind_of(Integer))
      expect(response).to redirect_to(export_entries_path(year: '2021'))
      expect(user.exports.last).to have_attributes(scope: 'year:2021', year: '2021', search_term: nil, description: 'Entries from 2021')
      expect(user.exports.last.filename).to match(/\Adabble-me-2021-\d{4}-\d\d-\d\d\.zip\z/)

      expect { post export_entries_path, params: { search: { term: 'coffee' } } }.to have_enqueued_job(ExportEntriesJob).with(kind_of(Integer))
      export = user.exports.last
      expect(response).to redirect_to(export_entries_path(search: { term: 'coffee' }))
      expect(export.scope).to match(/\Asearch:\h{64}\z/)
      expect(export).to have_attributes(search_term: 'coffee', description: 'Entries matching “coffee”')
      expect(export.filename).to match(/\Adabble-me-search-coffee-\d{4}-\d\d-\d\d\.zip\z/)
    end

    it 'keeps the search words out of the database in plain text' do
      post export_entries_path, params: { search: { term: 'coffee' } }

      expect(stored_value(user.exports.last, :search_term)).not_to include('coffee')
      expect(ciphertext?(stored_value(user.exports.last, :search_term))).to be(true)
    end

    it 'rejects a year that is not one' do
      expect { post export_entries_path, params: { year: '21; drop' } }.not_to(change { Export.count })
      expect(response).to redirect_to(export_entries_path)
    end

    it 'does not queue a second export of the same thing while one is being prepared' do
      user.exports.create!
      expect { post export_entries_path }.not_to(change { Export.count })
      expect(flash[:notice]).to include('already being prepared')
    end

    it 'downloads the last export when the same thing is asked for again within 12 hours' do
      last = user.exports.create!(status: 'ready', storage_key: 'exports/x.zip', expires_at: 6.days.from_now, created_at: 11.hours.ago)

      expect { post export_entries_path }.not_to(change { Export.count })
      expect(response).to redirect_to(download_export_path(last))

      follow_redirect!
      expect(response.location).to include('exports/x.zip')
      expect(last.reload.download_count).to eq(1)
    end

    it 'does the same for a year and for a search, matching the search whatever its case' do
      year = user.exports.create!(status: 'ready', scope: Export.scope_for(year: '2021'), storage_key: 'exports/y.zip', expires_at: 6.days.from_now)
      search = user.exports.create!(status: 'ready', scope: Export.scope_for(search_term: 'coffee'), storage_key: 'exports/s.zip', expires_at: 6.days.from_now)

      post export_entries_path, params: { year: '2021' }
      expect(response).to redirect_to(download_export_path(year))

      post export_entries_path, params: { search: { term: ' Coffee ' } }
      expect(response).to redirect_to(download_export_path(search))
    end

    it 'treats "coffee OR tea" and "coffee or tea" as different searches, as search itself does' do
      user.exports.create!(status: 'ready', scope: Export.scope_for(search_term: 'coffee OR tea'), storage_key: 'exports/s.zip', expires_at: 6.days.from_now)

      expect { post export_entries_path, params: { search: { term: 'coffee or tea' } } }.to change { user.exports.count }.by(1)
    end

    it 'starts a new export for something else inside those 12 hours' do
      user.exports.create!(status: 'ready', storage_key: 'exports/x.zip', expires_at: 6.days.from_now)
      user.exports.create!(status: 'ready', scope: Export.scope_for(search_term: 'coffee'), storage_key: 'exports/s.zip', expires_at: 6.days.from_now)

      expect { post export_entries_path, params: { year: '2021' } }.to change { user.exports.count }.by(1)
      expect { post export_entries_path, params: { search: { term: 'tea' } } }.to change { user.exports.count }.by(1)
    end

    it 'starts a new export of the same thing once 12 hours have passed, or after a failure' do
      user.exports.create!(status: 'ready', storage_key: 'exports/x.zip', expires_at: 6.days.from_now, created_at: 13.hours.ago)
      user.exports.create!(status: 'failed', created_at: 2.hours.ago)

      expect { post export_entries_path }.to change { user.exports.count }.by(1)
    end

    it 'stops at ten exports an hour, however varied' do
      Export::HOURLY_LIMIT.times { |n| user.exports.create!(status: 'ready', scope: "year:#{2000 + n}") }

      expect { post export_entries_path }.not_to(change { Export.count })
      expect(flash[:alert]).to include('try again later')
    end
  end
end
