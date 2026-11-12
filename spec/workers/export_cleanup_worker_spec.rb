require 'rails_helper'

RSpec.describe ExportCleanupWorker do
  include_context 'with export storage'

  let(:user) { FactoryBot.create(:user) }
  let(:store) { ExportStore.new }

  def stored_export(expires_at:)
    export = user.exports.create!
    path = Pathname(Dir.mktmpdir).join('export.zip')
    path.binwrite('zip bytes')
    key = store.upload(ExportStore.key_for(export), path.to_s)
    export.ready!(storage_key: key, byte_size: 9, entry_count: 1, image_count: 0, skipped_image_count: 0)
    export.update_columns(expires_at: expires_at)
    export
  end

  it 'deletes the files of expired exports and leaves current ones' do
    expired = stored_export(expires_at: 1.hour.ago)
    current = stored_export(expires_at: 3.days.from_now)
    expired_key = expired.storage_key

    described_class.new.perform

    expect(store.exist?(expired_key)).to be(false)
    expect(expired.reload).to have_attributes(status: 'expired', storage_key: nil)
    expect(store.exist?(current.storage_key)).to be(true)
    expect(current.reload.status).to eq('ready')
  end

  it 'marks an export that never finished as failed' do
    stuck = user.exports.create!
    stuck.update_columns(created_at: 7.hours.ago)
    fresh = user.exports.create!

    described_class.new.perform

    expect(stuck.reload.status).to eq('failed')
    expect(fresh.reload.status).to eq('preparing')
  end

  it 'deletes the file when the export or its owner is deleted' do
    export = stored_export(expires_at: 3.days.from_now)
    key = export.storage_key

    user.destroy

    expect(store.exist?(key)).to be(false)
    expect(Export.where(id: export.id)).to be_empty
  end
end
