require 'rails_helper'

describe 'Search' do
  include_context 'has all objects'

  it 'shows matching entries with export outside the AI connector card' do
    paid_entry.update!(body: 'Katelyn got so drunk she does not remember a thing.')
    sign_in paid_user
    visit search_path(search: { term: 'a thing' })

    expect(page).to have_content('remember a thing')
    expect(page).to have_css('.s-search-export a', text: 'Export Search Entries')
    expect(page).to have_link('How to use the AI Connector', href: mcp_server_docs_path)
    expect(page).to have_css('.email-post-card .btn-primary', text: 'How to use the AI Connector')
    expect(page).not_to have_css('.email-address-box')
    expect(page).not_to have_css('code', text: 'AI connector')
    expect(page).not_to have_css('.email-post-card a', text: 'Export Search Entries')
  end
end
