# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OauthIdleTokenWorker do
  let(:user) { create(:user) }
  let(:claude) do
    Doorkeeper::Application.create!(name: 'Claude', redirect_uri: 'https://claude.ai/api/mcp/auth_callback',
                                    scopes: 'mcp:access', confidential: false)
  end
  let(:mobile_app) { MobileApp.ensure_application! }

  def token(application, created_at:, expires_in: 1.day.to_i, revoked_at: nil)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id,
                                    scopes: application.scopes.to_s, expires_in: expires_in,
                                    use_refresh_token: true, created_at: created_at, revoked_at: revoked_at)
  end

  it 'revokes tokens idle past their limit and leaves apps still in use alone' do
    idle_connector = token(claude, created_at: 31.days.ago)
    active_connector = token(claude, created_at: 2.hours.ago)
    quiet_connector = token(claude, created_at: 29.days.ago)
    idle_phone = token(mobile_app, created_at: 366.days.ago)
    quiet_phone = token(mobile_app, created_at: 200.days.ago)
    no_expiry = token(claude, created_at: 90.days.ago, expires_in: nil)
    already_revoked = token(claude, created_at: 90.days.ago, revoked_at: 60.days.ago)

    expect(described_class.new.perform).to eq(2)

    expect([idle_connector, idle_phone].map { |t| t.reload.revoked? }).to all(be(true))
    expect([active_connector, quiet_connector, quiet_phone, no_expiry].map { |t| t.reload.revoked? }).to all(be(false))
    expect(already_revoked.reload.revoked_at).to be_within(1.second).of(60.days.ago)
  end
end
