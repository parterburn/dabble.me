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
      expect(response).to redirect_to(edit_user_registration_path(anchor: 'export'))

      get download_export_path(export)
      expect(response).to redirect_to(edit_user_registration_path(anchor: 'export'))
      expect(export.reload.download_count).to eq(0)
    end
  end

  describe 'downloading' do
    before { sign_in user }

    it 'redirects to a storage link that lasts minutes, and records the download' do
      get download_export_path(export)

      location = response.headers['Location']
      expect(location).to start_with('https://').and include(export.storage_key, 'X-Amz-Expires=300')
      expect(location).to include("dabble-me-export-#{export.created_at.strftime('%Y-%m-%d')}.zip")
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

  describe 'requesting an export' do
    before { sign_in user }

    it 'queues a ZIP and promises a link by email' do
      FactoryBot.create(:entry, user: user, body: 'one entry')

      expect { get export_entries_path }.to change { user.exports.count }.by(1)
      expect(response).to redirect_to(edit_user_registration_path(anchor: 'export'))
      expect(flash[:notice]).to include('email you a link')
      expect(user.exports.last.status).to eq('preparing')
    end

    it 'streams the journal as Markdown right away, without creating an export' do
      FactoryBot.create(:entry, user: user, body: '<p>one <b>entry</b></p>', date: Time.utc(2026, 3, 1, 12))
      FactoryBot.create(:entry, user: user, body: '<p>an older one</p>', date: Time.utc(2021, 3, 1, 12))
      FactoryBot.create(:entry, body: 'someone else')

      expect { get export_entries_path(format: :md) }.not_to(change { Export.count })
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/markdown')
      expect(response.headers['Content-Disposition']).to match(/attachment; filename="dabble-me-\d{4}-\d\d-\d\d\.md"/)
      expect(response.body).to eq("# Dabble Me journal\n\n## 2021-03-01 (Monday)\n\nan older one\n\n## 2026-03-01 (Sunday)\n\none **entry**\n\n")
    end

    it 'streams only one year or one search as Markdown when asked' do
      FactoryBot.create(:entry, user: user, body: '<p>coffee in 2026</p>', date: Time.utc(2026, 3, 1, 12))
      FactoryBot.create(:entry, user: user, body: '<p>tea in 2021</p>', date: Time.utc(2021, 3, 1, 12))

      get export_entries_path(year: '2021', format: :md)
      expect(response.body).to include('tea in 2021')
      expect(response.body).not_to include('coffee in 2026')
      expect(response.headers['Content-Disposition']).to include('dabble-me-2021-')

      get export_entries_path(search: { term: 'coffee' }, format: :md)
      expect(response.body).to include('coffee in 2026')
      expect(response.body).not_to include('tea in 2021')
    end

    it 'never sends entry text when a ZIP is asked for, whatever format an old link names' do
      FactoryBot.create(:entry, user: user, body: 'one entry')

      expect { get export_entries_path(format: :txt) }.to change { user.exports.count }.by(1)
      expect(response).to have_http_status(:redirect)
      expect(response.body).not_to include('one entry')
    end

    it 'passes a year or a search on to the job, and returns to the page it came from' do
      expect { get export_entries_path(year: '2021'), headers: { 'HTTP_REFERER' => entries_url } }
        .to have_enqueued_job(ExportEntriesJob).with(kind_of(Integer), { year: '2021' })
      expect(response).to redirect_to(entries_url)
      expect(user.exports.last.scope).to eq('year:2021')

      expect { get export_entries_path(search: { term: 'coffee' }) }
        .to have_enqueued_job(ExportEntriesJob).with(kind_of(Integer), { search_term: 'coffee' })
      expect(user.exports.last.scope).to match(/\Asearch:\h{64}\z/)
      expect(user.exports.last.scope).not_to include('coffee')
    end

    it 'does not queue a second export of the same thing while one is being prepared' do
      user.exports.create!
      expect { get export_entries_path }.not_to(change { Export.count })
      expect(flash[:notice]).to include('already being prepared')
    end

    it 'downloads the last export when the same thing is asked for again within 12 hours' do
      last = user.exports.create!(status: 'ready', storage_key: 'exports/x.zip', expires_at: 6.days.from_now, created_at: 11.hours.ago)

      expect { get export_entries_path }.not_to(change { Export.count })
      expect(response).to redirect_to(download_export_path(last))

      follow_redirect!
      expect(response.location).to include('exports/x.zip')
      expect(last.reload.download_count).to eq(1)
    end

    it 'does the same for a year and for a search, matching the search whatever its case' do
      year = user.exports.create!(status: 'ready', scope: Export.scope_for(year: '2021'), storage_key: 'exports/y.zip', expires_at: 6.days.from_now)
      search = user.exports.create!(status: 'ready', scope: Export.scope_for(search_term: 'coffee'), storage_key: 'exports/s.zip', expires_at: 6.days.from_now)

      get export_entries_path(year: '2021')
      expect(response).to redirect_to(download_export_path(year))

      get export_entries_path(search: { term: ' Coffee ' })
      expect(response).to redirect_to(download_export_path(search))
    end

    it 'starts a new export for something else inside those 12 hours' do
      user.exports.create!(status: 'ready', storage_key: 'exports/x.zip', expires_at: 6.days.from_now)
      user.exports.create!(status: 'ready', scope: Export.scope_for(search_term: 'coffee'), storage_key: 'exports/s.zip', expires_at: 6.days.from_now)

      expect { get export_entries_path(year: '2021') }.to change { user.exports.count }.by(1)
      expect { get export_entries_path(search: { term: 'tea' }) }.to change { user.exports.count }.by(1)
    end

    it 'starts a new export of the same thing once 12 hours have passed, or after a failure' do
      user.exports.create!(status: 'ready', storage_key: 'exports/x.zip', expires_at: 6.days.from_now, created_at: 13.hours.ago)
      user.exports.create!(status: 'failed', created_at: 2.hours.ago)

      expect { get export_entries_path }.to change { user.exports.count }.by(1)
    end

    it 'stops at ten exports an hour, however varied' do
      Export::HOURLY_LIMIT.times { |n| user.exports.create!(status: 'ready', scope: "year:#{2000 + n}") }

      expect { get export_entries_path }.not_to(change { Export.count })
      expect(flash[:alert]).to include('try again later')
    end
  end
end
