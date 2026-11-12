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

      expect { get export_entries_path(format: :zip) }.to change { user.exports.count }.by(1)
      expect(response).to redirect_to(edit_user_registration_path(anchor: 'export'))
      expect(flash[:notice]).to include('email you a link')
      expect(user.exports.last.status).to eq('preparing')
    end

    it 'sends a large text export the same way' do
      Entry.insert_all(101.times.map { |day| { user_id: user.id, date: Time.utc(2020, 1, 1) + day.days, body: 'x', created_at: Time.current, updated_at: Time.current } })

      expect { get export_entries_path(format: :txt) }.to change { user.exports.count }.by(1)
    end

    it 'still downloads a small text export on the spot' do
      FactoryBot.create(:entry, user: user, body: 'one entry')

      expect { get export_entries_path(format: :txt) }.not_to(change { Export.count })
      expect(response).to have_http_status(:ok)
    end

    it 'does not queue a second export while one is being prepared' do
      user.exports.create!
      expect { get export_entries_path(format: :zip) }.not_to(change { Export.count })
      expect(flash[:notice]).to include('already being prepared')
    end

    it 'limits how many can be requested in a day' do
      Export::DAILY_LIMIT.times { user.exports.create!(status: 'ready') }
      expect { get export_entries_path(format: :zip) }.not_to(change { Export.count })
      expect(flash[:alert]).to include('try again tomorrow')
    end
  end
end
