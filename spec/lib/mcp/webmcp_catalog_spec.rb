# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::WebmcpCatalog do
  subject(:catalog) { described_class.new(base_url: 'https://dabble.me') }

  it 'keeps the Server Card description within the registry limit' do
    expect(catalog.server_card.fetch('description').length).to be_between(1, 100)
  end

  it 'lists only read-only public tools and documents remote journal tools separately' do
    expect(catalog.public_tool_names).to eq(
      %w[get_product_overview get_mcp_connection list_remote_mcp_tools list_reference_pages]
    )
    expect(catalog.webmcp_manifest.dig('remoteMcp', 'authentication', 'scope')).to eq('mcp:access')
    expect(catalog.invoke_public_tool('get_mcp_connection').dig('content', 0, 'text')).to include('https://dabble.me/mcp')
    expect(catalog.invoke_public_tool('missing')).to be_nil
    expect(catalog.webmcp_manifest['tools'].map { |tool| tool['name'] }).to include('search_journal_entries', 'draft_journal_entry')
    expect(catalog.webmcp_manifest['tools'].find { |tool| tool['name'] == 'search_journal_entries' }['authentication']).to eq('cookie-session')
  end

  it 'exposes session tool config only as metadata, not journal contents' do
    user = create(:user, plan: 'PRO Monthly PayHere', first_name: 'Ada')
    signed_in = described_class.new(base_url: 'https://dabble.me', user: user)

    expect(signed_in.page_config['signedIn']).to eq(true)
    expect(signed_in.page_config['isPro']).to eq(true)
    expect(signed_in.page_config['firstName']).to eq('Ada')
    expect(signed_in.page_config['tools'].map { |tool| tool['name'] }).to include('draft_journal_entry')
  end

  it 'builds RFC 8288 Link values for HTML discovery' do
    expect(catalog.link_header_values.join).to include('rel="webmcp"')
    expect(catalog.html_links.map { |link| link[:rel] }).to include('describedby', 'ai-catalog', 'api-catalog', 'mcp-server-card')
  end
end
