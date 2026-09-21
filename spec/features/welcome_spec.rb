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
    expect(footer_lists[1]).not_to have_link('Support')
  end

  it 'has correct title for FAQs page' do
    visit support_path
    expect(page).to have_title 'Support and FAQs — Dabble me.'
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
    expect(page).to have_content 'How should an AI assistant attach a photo'
    expect(page).to have_content 'Prefer create_entry with image_url'
    expect(page).to have_content 'Claude can’t upload a photo'
    expect(page).to have_css('script[type="application/ld+json"]', visible: false)

    description = page.find('meta[name="description"]', visible: false)['content']
    canonical = page.find('link[rel="canonical"]', visible: false)['href']
    expect(description).to include('ChatGPT, Claude')
    expect(canonical).to end_with('/mcp-server')
    expect(page).to have_css('link[rel="webmcp"]', visible: false)
    expect(page).to have_css('script#dabble-webmcp-config', visible: false)
    expect(page).to have_content('WebMCP manifest')
  end

  it 'publishes an accurate Day One AI journaling comparison' do
    visit day_one_ai_journaling_path

    expect(page).to have_title 'Dabble Me vs. Day One for AI Journaling and MCP — Dabble me.'
    expect(page).to have_content 'Remote connector vs. local connector'
    expect(page).to have_content 'Mobile and desktop ChatGPT / Claude apps'
    expect(page).to have_content 'Desktop Mac setup — not a mobile-first connector'
    expect(page).to have_content 'Remote Streamable HTTP'
    expect(page).to have_content 'Local stdio process'
    expect(page).to have_link('official MCP guide')
    expect(page).to have_link('Day One alternative & journal import', href: day_one_alternative_path)
  end

  it 'publishes a Day One alternative page focused on import and email journaling' do
    visit day_one_alternative_path

    expect(page).to have_title 'Day One Alternative: Import Your Journal into Dabble Me — Dabble me.'
    expect(page).to have_content 'Import Day One. Journal by email.'
    expect(page).to have_content 'export your journal as JSON'
    expect(page).to have_link('Open the Day One importer', href: import_path('day_one'))
    expect(page).to have_link('Dabble Me vs. Day One for AI journaling', href: day_one_ai_journaling_path)
    expect(page).to have_css('script[type="application/ld+json"]', visible: false)

    description = page.find('meta[name="description"]', visible: false)['content']
    expect(description).to include('Day One alternative')
  end

  it 'publishes a guide to journaling apps with MCP' do
    visit best_journaling_apps_with_mcp_path

    expect(page).to have_title 'Best Journaling Apps with MCP / Claude and ChatGPT Connectors — Dabble me.'
    expect(page).to have_content 'Best journaling apps with MCP'
    expect(page).to have_content 'Claude & ChatGPT Connectors'
    expect(page).to have_content 'How this guide evaluates an AI journal with MCP'
    expect(page).to have_content 'Prompts that show why MCP matters'
    expect(page).to have_content 'Using voice in my favorite AI tool, help me process my day out loud'
    expect(page).to have_content 'Dabble Me'
    expect(page).to have_content 'Day One'
    expect(page).to have_content 'Find every time I mentioned burnout'

    page_text = page.text
    expect(page_text.index('Prompts that show why MCP matters')).to be < page_text.index('1. Dabble Me')
  end

  describe 'SEO metadata' do
    DEFAULT_DESCRIPTION = 'The simple, private journal that helps you actually write.'.freeze

    def json_ld_nodes
      page.all('script[type="application/ld+json"]', visible: false).flat_map do |script|
        data = JSON.parse(script.native.text)
        data['@graph'] || [data]
      end
    end

    def meta_description
      page.find('meta[name="description"]', visible: false)['content']
    end

    it 'describes the organization, website, and app on the homepage' do
      visit root_path

      types = json_ld_nodes.map { |node| node['@type'] }
      expect(types).to contain_exactly('Organization', 'WebSite', 'WebApplication')

      organization = json_ld_nodes.find { |node| node['@type'] == 'Organization' }
      expect(organization['name']).to eq 'Dabble Me'
      expect(organization['legalName']).to eq 'Dabble Dev LLC'
      expect(organization['sameAs']).to include('https://github.com/parterburn/dabble.me')

      application = json_ld_nodes.find { |node| node['@type'] == 'WebApplication' }
      expect(application['offers'].map { |offer| offer['price'] }).to eq %w[0.00 4.00 40.00]
      expect(application).not_to have_key('aggregateRating')
    end

    it 'publishes pricing schema and a unique description on the Subscribe page' do
      visit subscribe_path

      expect(json_ld_nodes.map { |node| node['@type'] }).to contain_exactly('Organization', 'WebApplication')
      expect(meta_description).to include('$4/month or $40/year')
      expect(meta_description).not_to start_with(DEFAULT_DESCRIPTION)
    end

    it 'has unique descriptions for Support and the OhLife alternative page' do
      visit support_path
      support_description = meta_description
      visit ohlife_alternative_path
      ohlife_description = meta_description

      expect([support_description, ohlife_description]).to all(satisfy { |text| !text.start_with?(DEFAULT_DESCRIPTION) })
      expect(support_description).not_to eq ohlife_description
      expect([support_description, ohlife_description]).to all(satisfy { |text| text.length <= 165 })
    end

    it 'gives the OhLife and Day One alternative pages at least 600 words of content' do
      visit ohlife_alternative_path
      expect(page.find('main').text.split.size).to be >= 600
      expect(page).to have_link('Entries → Import → OhLife', href: import_path('ohlife'))
      expect(page).to have_link('photo importer', href: import_path('photos'))

      visit day_one_alternative_path
      expect(page.find('main').text.split.size).to be >= 600
    end

    it 'gives every article the properties Google recommends' do
      [day_one_alternative_path, day_one_ai_journaling_path, best_journaling_apps_with_mcp_path, mcp_server_docs_path].each do |path|
        visit path

        article = json_ld_nodes.find { |node| %w[Article TechArticle].include?(node['@type']) }
        expect(article).to be_present, "no Article schema on #{path}"
        expect(article['datePublished']).to match(/\A\d{4}-\d{2}-\d{2}\z/)
        expect(article['dateModified']).to match(/\A\d{4}-\d{2}-\d{2}\z/)
        expect(article['image']).to end_with('/dabble_logo_ogimage.jpg')
        expect(article.dig('publisher', 'name')).to eq 'Dabble Me'
        expect(article.dig('mainEntityOfPage', '@id')).to eq article['url']
      end
    end

    it 'keeps the FAQ markup on the MCP page next to the TechArticle' do
      visit mcp_server_docs_path

      expect(json_ld_nodes.map { |node| node['@type'] }).to contain_exactly('TechArticle', 'FAQPage')
    end

    it 'noindexes login, sign-up, and password pages' do
      [new_user_session_path, new_user_registration_path, new_user_password_path].each do |path|
        visit path
        expect(page).to have_css('meta[name="robots"][content="noindex, follow"]', visible: false), "#{path} is indexable"
      end
    end

    it 'leaves marketing pages indexable' do
      [root_path, support_path, subscribe_path, ohlife_alternative_path].each do |path|
        visit path
        expect(page).not_to have_css('meta[name="robots"]', visible: false), "#{path} has a robots meta tag"
      end
    end

    it 'loads jQuery only on the passkey forms' do
      [new_user_session_path, new_user_registration_path].each do |path|
        visit path
        expect(page).to have_css('script[src*="jquery"]', visible: false)
      end

      [root_path, support_path, subscribe_path, ohlife_alternative_path, day_one_alternative_path].each do |path|
        visit path
        expect(page).not_to have_css('script[src*="jquery"]', visible: false), "#{path} still loads jQuery"
      end
    end
  end
end
