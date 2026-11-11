require 'rails_helper'

RSpec.describe OauthAppCleanupWorker do
  let(:user) { create(:user) }

  def register(created_at: 60.days.ago, confidential: false, scopes: 'mcp:access')
    Doorkeeper::Application.create!(name: 'Claude', redirect_uri: 'https://claude.ai/api/mcp/auth_callback',
                                    scopes: scopes, confidential: confidential, created_at: created_at)
  end

  def token(application, created_at:, revoked_at: nil)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id, scopes: 'mcp:access',
                                    expires_in: 1.day.to_i, created_at: created_at, revoked_at: revoked_at)
  end

  it 'deletes old self-registered clients nobody uses, and keeps the rest' do
    never_used = register
    abandoned = register.tap { |app| token(app, created_at: 50.days.ago, revoked_at: 45.days.ago) }
    new_registration = register(created_at: 10.days.ago)
    connected = register.tap { |app| token(app, created_at: 50.days.ago) }
    recently_revoked = register.tap { |app| token(app, created_at: 5.days.ago, revoked_at: 1.day.ago) }
    recent_grant = register.tap do |app|
      Doorkeeper::AccessGrant.create!(application: app, resource_owner_id: user.id, redirect_uri: app.redirect_uri,
                                      expires_in: 600, scopes: 'mcp:access', created_at: 2.days.ago)
    end
    admin_made = register(confidential: true)
    mobile = MobileApp.ensure_application!.tap { |app| app.update_columns(created_at: 60.days.ago) }

    expect(described_class.new.perform).to eq(2)

    expect(Doorkeeper::Application.exists?(never_used.id)).to be(false)
    expect(Doorkeeper::Application.exists?(abandoned.id)).to be(false)
    expect(Doorkeeper::AccessToken.where(application_id: abandoned.id)).to be_empty
    [new_registration, connected, recently_revoked, recent_grant, admin_made, mobile].each do |kept|
      expect(Doorkeeper::Application.exists?(kept.id)).to be(true), "expected #{kept.inspect} to be kept"
    end
  end
end
