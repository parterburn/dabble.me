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
    expect(sitemap).to include("#{public_url}/day-one-alternative")
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

  it 'publishes a WebMCP manifest for AI-client discovery' do
    get '/.well-known/webmcp'

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/json')
    expect(response.headers['Access-Control-Allow-Origin']).to eq('*')
    json = JSON.parse(response.body)
    expect(json.dig('site', 'name')).to eq('Dabble Me')
    expect(json['tools'].map { |tool| tool['name'] }).to include(
      'get_product_overview',
      'get_mcp_connection',
      'list_remote_mcp_tools',
      'list_reference_pages'
    )
    expect(json.dig('remoteMcp', 'url')).to end_with('/mcp')
    expect(json.dig('remoteMcp', 'tools').map { |tool| tool['name'] }).to include('search_entries')
    expect(json.dig('links', 'llms_txt')).to end_with('/llms.txt')
  end

  it 'redirects the legacy WebMCP.json alias to the extensionless manifest' do
    get '/.well-known/webmcp.json'

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to('http://www.example.com/.well-known/webmcp')
  end

  it 'publishes an MCP Server Card and AI Catalog' do
    get '/mcp/server-card'

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/mcp-server-card+json')
    card = JSON.parse(response.body)
    expect(card['$schema']).to eq('https://static.modelcontextprotocol.io/schemas/v1/server-card.schema.json')
    expect(card['name']).to eq('io.github.parterburn/dabble-me')
    expect(card.fetch('description').length).to be_between(1, 100)
    expect(card['remotes']).to include(
      hash_including('type' => 'streamable-http', 'url' => a_string_ending_with('/mcp'))
    )

    get '/.well-known/mcp.json'
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['name']).to eq(card['name'])

    get '/.well-known/ai-catalog.json'
    expect(response).to have_http_status(:ok)
    catalog = JSON.parse(response.body)
    expect(catalog['specVersion']).to eq('1.0')
    expect(catalog['entries'].first['type']).to eq('application/mcp-server-card+json')
    expect(catalog['entries'].first['url']).to end_with('/mcp/server-card')
  end

  it 'advertises WebMCP from HTML pages and public reference tools' do
    get '/'

    expect(response).to have_http_status(:ok)
    expect(response.headers['Link']).to include('rel="webmcp"')
    expect(response.headers['Link']).to include('rel="mcp-server-card"')
    expect(response.body).to include('rel="webmcp"')
    expect(response.body).to include('id="dabble-webmcp-config"')
    expect(response.body).to include('/webmcp.js')

    get '/webmcp/tools/get_product_overview'
    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload['isError']).to eq(false)
    expect(payload.dig('content', 0, 'text')).to include('email-first personal journal')

    get '/webmcp/tools/not_a_real_tool'
    expect(response).to have_http_status(:not_found)
  end

  it 'annotates public account forms for declarative WebMCP' do
    get '/users/sign_up'
    expect(response.body).to include('toolname="create_account"')
    expect(response.body).to include('toolparamdescription="Email address that will receive journal prompts."')

    get '/users/sign_in'
    expect(response.body).to include('toolname="log_in"')
  end
end
