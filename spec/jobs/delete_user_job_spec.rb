require 'rails_helper'

RSpec.describe DeleteUserJob, type: :job do
  include_context 'has all objects'

  it 'does not delete the user when deletion was cancelled' do
    expect do
      described_class.perform_now(user.id)
    end.not_to change(User, :count)

    expect(user.reload).to be_persisted
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
