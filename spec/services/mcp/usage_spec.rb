require "rails_helper"

RSpec.describe Mcp::Usage do
  def grant_mcp!(user, name: "Claude")
    app = Doorkeeper::Application.find_or_create_by!(uid: "rspec-#{name.parameterize}") do |record|
      record.name = name
      record.redirect_uri = "http://127.0.0.1/cb"
      record.scopes = "mcp:access"
      record.confidential = false
    end
    Doorkeeper::AccessToken.create!(
      resource_owner_id: user.id,
      application_id: app.id,
      scopes: "mcp:access",
      expires_in: 2.hours
    )
  end

  it "counts live OAuth connections separately from tool usage" do
    connected = create(:user)
    active = create(:user)
    grant_mcp!(connected, name: "Claude")
    grant_mcp!(active, name: "ChatGPT")
    create(:mcp_tool_invocation, user: active, tool_name: "search_entries", created_at: 2.days.ago)
    create(:mcp_tool_invocation, user: active, tool_name: "list_entries", source: "webmcp", created_at: 1.hour.ago)

    summary = described_class.new.summary

    expect(summary[:connected_now]).to eq(2)
    expect(summary[:connected_ever]).to eq(2)
    expect(summary[:active_users_7d]).to eq(1)
    expect(summary[:calls_7d]).to eq(2)
    expect(summary[:oauth_calls_30d]).to eq(1)
    expect(summary[:webmcp_calls_30d]).to eq(1)
    expect(summary[:tools].map { |row| row[:name] }).to include("search_entries", "list_entries")
    expect(summary[:clients].map { |row| row[:name] }).to include("Claude", "ChatGPT")
  end

  it "ignores revoked and expired tokens for connected_now" do
    user = create(:user)
    token = grant_mcp!(user)
    token.update!(revoked_at: Time.current)

    expired = create(:user)
    stale = grant_mcp!(expired, name: "Expired")
    stale.update_columns(created_at: 4.hours.ago, expires_in: 60)

    expect(described_class.new.connected_now).to eq(0)
    expect(described_class.new.connected_ever).to eq(2)
  end
end
