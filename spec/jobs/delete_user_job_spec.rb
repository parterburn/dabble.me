require 'rails_helper'

RSpec.describe DeleteUserJob, type: :job do
  include_context 'has all objects'

  it 'does not delete the user when deletion was cancelled' do
    expect do
      described_class.perform_now(user.id)
    end.not_to change(User, :count)

    expect(user.reload).to be_persisted
  end

  it 'leaves a deletion asked for again to its own job' do
    first = 2.hours.ago
    user.update_column(:deleted_at, 30.minutes.ago) # cancelled after `first`, then asked for again

    expect do
      described_class.perform_now(user.id, first.to_i)
    end.not_to change(User, :count)
  end

  it 'deletes the user when the deletion it was scheduled for still stands' do
    user.update_column(:deleted_at, 1.hour.ago)

    expect do
      described_class.perform_now(user.id, user.reload.deleted_at.to_i)
    end.to change(User, :count).by(-1)
  end

  describe 'exports' do
    include_context 'with export storage'

    it "deletes the account's export files with it" do
      user.update_column(:deleted_at, Time.current)
      export = user.exports.create!
      path = Pathname(Dir.mktmpdir).join('export.zip')
      path.binwrite('zip bytes')
      store = ExportStore.new
      key = store.upload(ExportStore.key_for(export), path.to_s)
      export.ready!(storage_key: key, byte_size: 9, entry_count: 1, image_count: 0, skipped_image_count: 0)

      described_class.perform_now(user.id)

      expect(store.exist?(key)).to be(false)
      expect(Export.where(id: export.id)).to be_empty
    end
  end

  it 'keeps the account when it is signed back into while the entries are going' do
    user.update_column(:deleted_at, 1.hour.ago)
    requested_at = user.reload.deleted_at.to_i
    create(:entry, user: user)
    allow_any_instance_of(Entry).to receive(:destroy).and_wrap_original do |original|
      user.cancel_pending_deletion!
      original.call
    end

    expect do
      described_class.perform_now(user.id, requested_at)
    end.not_to change(User, :count)
    expect(user.reload.deleted_at).to be_nil
  end

  it 'deletes the user when deletion is still pending' do
    user.update_column(:deleted_at, Time.current)

    expect do
      described_class.perform_now(user.id)
    end.to change(User, :count).by(-1)
  end

  it 'deletes the user cleanly even when Doorkeeper OAuth grants and tokens exist' do
    app = Doorkeeper::Application.create!(
      name: 'MCP Client',
      redirect_uri: 'http://127.0.0.1/cb',
      confidential: false,
      scopes: 'mcp:access'
    )
    Doorkeeper::AccessGrant.create!(
      resource_owner_id: user.id,
      application_id: app.id,
      token: SecureRandom.hex(32),
      expires_in: 600,
      redirect_uri: 'http://127.0.0.1/cb',
      scopes: 'mcp:access',
      created_at: Time.current,
      revoked_at: Time.current
    )
    Doorkeeper::AccessToken.create!(
      resource_owner_id: user.id,
      application_id: app.id,
      scopes: 'mcp:access',
      expires_in: 7200
    )

    user.update_column(:deleted_at, Time.current)

    expect do
      described_class.perform_now(user.id)
    end.to change(User, :count).by(-1)
      .and change { Doorkeeper::AccessGrant.where(resource_owner_id: user.id).count }.from(1).to(0)
      .and change { Doorkeeper::AccessToken.where(resource_owner_id: user.id).count }.from(1).to(0)
  end
end
