# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserSessionCleanupWorker do
  let(:user) { create(:user) }
  let(:mobile_app) { MobileApp.ensure_application! }

  def app_row(token_revoked:, updated_at: 2.days.ago)
    row = user.user_sessions.create!(kind: "ios_app", last_active_at: updated_at, updated_at: updated_at)
    Doorkeeper::AccessToken.create!(application: mobile_app, resource_owner_id: user.id, scopes: MobileApp::SCOPE,
                                    user_session_id: row.id, revoked_at: (Time.current if token_revoked))
    row
  end

  it "deletes browsers unseen for 30 days and apps with no live token, and keeps the rest" do
    old_browser = user.user_sessions.create!(kind: "web", last_active_at: 31.days.ago)
    recent_browser = user.user_sessions.create!(kind: "web", last_active_at: 29.days.ago)
    signed_out_app = app_row(token_revoked: true)
    live_app = app_row(token_revoked: false)
    just_refreshed = app_row(token_revoked: true, updated_at: 1.hour.ago)

    expect(described_class.new.perform).to eq(2)
    expect(UserSession.where(id: [old_browser, signed_out_app].map(&:id))).to be_empty
    expect(UserSession.where(id: [recent_browser, live_app, just_refreshed].map(&:id)).count).to eq(3)
  end
end
