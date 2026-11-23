require 'rails_helper'

RSpec.describe ConnectedAppUsage do
  let(:user) { create(:user) }
  let(:application) do
    Doorkeeper::Application.create!(name: 'Claude', redirect_uri: 'https://claude.ai/api/mcp/auth_callback',
                                    scopes: 'mcp:access', confidential: false)
  end

  it 'is the later of the newest token and the last MCP call' do
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id, scopes: 'mcp:access',
                                    expires_in: 1.day.to_i, created_at: 10.days.ago)
    expect(described_class.last_used(user.id, [application.id])[application.id]).to be_within(1.second).of(10.days.ago)

    McpToolInvocation.create!(user_id: user.id, tool_name: 'list_entries', source: 'oauth',
                              oauth_application_id: application.id, created_at: 2.days.ago)
    expect(described_class.last_used(user.id, [application.id])[application.id]).to be_within(1.second).of(2.days.ago)
  end
end
