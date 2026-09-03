require "rails_helper"

RSpec.describe Mcp::InvocationLogger do
  it "stores tool name and counts without query text" do
    user = create(:user)

    described_class.record(
      user_id: user.id,
      tool_name: "search_entries",
      source: "oauth",
      success: true,
      result_count: 4,
      duration_ms: 12
    )

    log = McpToolInvocation.last
    expect(log.user_id).to eq(user.id)
    expect(log.tool_name).to eq("search_entries")
    expect(log.source).to eq("oauth")
    expect(log.success).to eq(true)
    expect(log.result_count).to eq(4)
    expect(log.attributes.values.map(&:to_s).join).not_to include("burnout")
  end

  it "does not raise when persistence fails" do
    allow(McpToolInvocation).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
    allow(Sentry).to receive(:capture_exception)

    expect {
      described_class.record(user_id: 1, tool_name: "search_entries", source: "oauth", success: true)
    }.not_to raise_error
    expect(Sentry).to have_received(:capture_exception)
  end

  it "reads result counts from search and create payloads" do
    search = MCP::Tool::Response.new([], structured_content: { total_matches: 9 })
    created = MCP::Tool::Response.new([], structured_content: { success: true })

    expect(described_class.result_count_from(search)).to eq(9)
    expect(described_class.result_count_from(created)).to eq(1)
  end
end
