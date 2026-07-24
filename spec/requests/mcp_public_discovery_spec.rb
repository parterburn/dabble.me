require 'rails_helper'

RSpec.describe 'Public MCP discovery', type: :request do
  let(:public_url) { "https://#{%w[dabble me].join('.')}" }

  it 'redirects the legacy settings URL to the dedicated documentation' do
    get '/settings/mcp'

    expect(response).to redirect_to('http://www.example.com/mcp-server')
  end

  it 'publishes AI-readable product and MCP documentation' do
    get '/llms.txt'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('AI journal with MCP')
    expect(response.body).to include("#{public_url}/mcp")
    expect(response.body).to include('search_entries')
  end

  it 'advertises the public pages in the sitemap and robots file' do
    sitemap = Nokogiri::XML(Rails.root.join('public/sitemap.xml').read).text
    robots = Rails.root.join('public/robots.txt').read

    expect(sitemap).to include("#{public_url}/mcp-server")
    expect(sitemap).to include("#{public_url}/dabble-me-vs-day-one-ai-journaling")
    expect(sitemap).to include("#{public_url}/best-journaling-apps-with-mcp")
    expect(robots).to include("Sitemap: #{public_url}/sitemap.xml")
  end

  it 'includes valid registry metadata for the remote server' do
    manifest = JSON.parse(Rails.root.join('server.json').read)

    expect(manifest).to include(
      '$schema' => 'https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json',
      'name' => 'io.github.parterburn/dabble-me',
      'title' => 'Dabble Me Journal',
      'version' => '1.0.0',
      'websiteUrl' => "#{public_url}/mcp-server"
    )
    expect(manifest.fetch('description').length).to be_between(1, 100)
    expect(manifest.fetch('remotes')).to include(
      'type' => 'streamable-http',
      'url' => "#{public_url}/mcp"
    )
  end
end
