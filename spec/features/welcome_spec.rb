require 'rails_helper'

describe 'Pages' do
  include_context 'has all objects'

  it 'has correct title for Root page' do
    visit root_path
    expect(page).to have_title 'Dabble me. Private email journaling & daily reflection.'
  end

  it 'groups Support beneath Pricing in the footer' do
    visit root_path

    footer_lists = page.all('footer ul')
    expect(footer_lists.first.all('a').map(&:text)).to eq(%w[Home Features Pricing Support])
    expect(footer_lists.second).not_to have_link('Support')
  end

  it 'has correct title for FAQs page' do
    visit support_path
    expect(page).to have_title 'Support — Dabble me.'
  end

  it 'explains mobile journaling through MCP AI connectors' do
    visit support_path

    expect(page).to have_content 'Is there a mobile app?'
    expect(page).to have_content 'connect Dabble Me to ChatGPT, Claude, or another MCP-compatible AI app'
    expect(page).to have_content 'use voice prompts where the AI app supports them'
    expect(page).to have_link('connect Dabble Me to ChatGPT, Claude, or another MCP-compatible AI app', href: mcp_server_docs_path)
  end

  it 'has correct title for Privacy page' do
    visit privacy_path
    expect(page).to have_title 'Privacy Policy — Dabble me.'
  end

  it 'has correct title for Terms page' do
    visit terms_path
    expect(page).to have_title 'Terms of Service — Dabble me.'
  end

  it 'has correct content for Subscribe page (redirects to homepage for non-logged-in users)' do
    visit subscribe_path
    expect(page).to have_content 'You\'ll have access to every premium feature.'
  end

  it 'publishes detailed, crawlable MCP documentation' do
    visit mcp_server_docs_path

    expect(page).to have_title 'Dabble Me MCP Server: Connect Your Journal to ChatGPT and Claude — Dabble me.'
    expect(page).to have_content 'AI journal with MCP'
    expect(page).to have_content 'journal app for ChatGPT'
    expect(page).to have_content 'Claude journal integration'
    expect(page).to have_content 'personal journal MCP server'
    expect(page).to have_content 'journal app for AI reflection'
    expect(page).to have_content 'search_entries'
    expect(page).to have_content 'get_image_upload_url'
    expect(page).to have_content 'Summarize my journal entries from last month'
    expect(page).to have_css('script[type="application/ld+json"]', visible: false)

    description = page.find('meta[name="description"]', visible: false)['content']
    canonical = page.find('link[rel="canonical"]', visible: false)['href']
    expect(description).to include('ChatGPT, Claude')
    expect(canonical).to end_with('/mcp-server')
  end

  it 'publishes an accurate Day One AI journaling comparison' do
    visit day_one_ai_journaling_path

    expect(page).to have_title 'Dabble Me vs. Day One for AI Journaling and MCP — Dabble me.'
    expect(page).to have_content 'Remote Streamable HTTP'
    expect(page).to have_content 'Local stdio process'
    expect(page).to have_link('official MCP guide')
  end

  it 'publishes a guide to journaling apps with MCP' do
    visit best_journaling_apps_with_mcp_path

    expect(page).to have_title 'Best Journaling Apps with MCP for ChatGPT and Claude — Dabble me.'
    expect(page).to have_content 'How this guide evaluates an AI journal with MCP'
    expect(page).to have_content 'Dabble Me'
    expect(page).to have_content 'Day One'
    expect(page).to have_content 'Find every time I mentioned burnout'
  end
end
