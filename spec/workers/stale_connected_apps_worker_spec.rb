require 'rails_helper'

RSpec.describe StaleConnectedAppsWorker do
  let(:now) { Time.zone.parse('2027-06-01 16:00') }
  let!(:user) { create(:user) }

  def register(name = 'Claude', created_at: now - 2.years)
    Doorkeeper::Application.create!(name: name, redirect_uri: 'https://claude.ai/api/mcp/auth_callback',
                                    scopes: 'mcp:access', confidential: false, created_at: created_at)
  end

  def token(application, created_at:, owner: user, revoked_at: nil)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: owner.id, scopes: 'mcp:access',
                                    expires_in: 1.day.to_i, created_at: created_at, revoked_at: revoked_at)
  end

  def call(application, at:, owner: user)
    McpToolInvocation.create!(user_id: owner.id, tool_name: 'search_entries', source: 'oauth',
                              oauth_application_id: application.id, created_at: at)
  end

  def deliveries = ActionMailer::Base.deliveries

  before { ActionMailer::Base.deliveries.clear }

  it 'emails once about connected apps unused for a year, and leaves the rest alone' do
    stale = register('Claude').tap { |app| token(app, created_at: now - 14.months) }
    recent_token = register('ChatGPT').tap { |app| token(app, created_at: now - 2.days) }
    recent_call = register('Cursor').tap do |app|
      token(app, created_at: now - 14.months)
      call(app, at: now - 3.months)
    end
    revoked = register('Old').tap { |app| token(app, created_at: now - 14.months, revoked_at: now - 13.months) }
    mobile = MobileApp.ensure_application!
    Doorkeeper::AccessToken.create!(application: mobile, resource_owner_id: user.id, scopes: MobileApp::SCOPE,
                                    expires_in: 1.day.to_i, created_at: now - 14.months)

    expect(ConnectedAppUsage.stale_by_user(now: now)).to eq(user.id => [stale.id])
    expect(described_class.deliver_all(now: now)).to eq(1)

    expect(deliveries.size).to eq(1)
    body = deliveries.last.text_part.body.decoded
    expect(body).to include('Claude (claude.ai): last used', '/security#connected-apps')
    [recent_token, recent_call, revoked].each { |app| expect(body).not_to include(app.name) }
    expect(StaleAppNotice.find_by(user_id: user.id, oauth_application_id: stale.id).last_used_at)
      .to be_within(1.second).of(now - 14.months)

    # Next week: nothing new to say.
    expect(described_class.deliver_all(now: now + 1.week)).to eq(0)
    expect(deliveries.size).to eq(1)
  end

  it 'names an app again only after it is used and then goes another year unused' do
    app = register.tap { |a| token(a, created_at: now - 14.months) }
    described_class.deliver_all(now: now)

    call(app, at: now + 1.month)
    expect(described_class.deliver_all(now: now + 6.months)).to eq(0)
    expect(described_class.deliver_all(now: now + 12.months)).to eq(0)
    expect(described_class.deliver_all(now: now + 13.months + 1.day)).to eq(1)
    expect(deliveries.size).to eq(2)
  end

  it 'waits MIN_GAP before emailing the same user about another app, then lists everything stale' do
    first = register('Claude').tap { |a| token(a, created_at: now - 14.months) }
    described_class.deliver_all(now: now)
    second = register('ChatGPT').tap { |a| token(a, created_at: now - 11.months - 3.weeks) }

    expect(described_class.deliver_all(now: now + 2.weeks)).to eq(0)
    expect(described_class.deliver_all(now: now + 91.days)).to eq(1)
    body = deliveries.last.text_part.body.decoded
    expect(body).to include(first.name, second.name)
  end

  it 'skips deleted accounts' do
    register.tap { |a| token(a, created_at: now - 14.months) }
    user.update_columns(deleted_at: now - 1.day)

    expect(described_class.deliver_all(now: now)).to eq(0)
    expect(deliveries).to be_empty
  end
end
