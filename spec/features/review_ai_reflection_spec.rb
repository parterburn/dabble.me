# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Year in review AI Reflection", type: :feature do
  include_context "has all objects"

  before do
    create(:entry, user: paid_user, body: "<p>A good year.</p>", date: Date.new(2026, 3, 1))
    sign_in paid_user
  end

  it "links straight to the Claude and ChatGPT plugins, with other apps going to the connector guide" do
    visit review_path(2026)

    expect(page).to have_css("h2", text: "AI Reflection")
    expect(page).to have_link("Add to Claude", href: ApplicationHelper.claude_plugin_directory_url)
    expect(page).to have_link("Add to ChatGPT", href: ApplicationHelper.chatgpt_plugin_directory_url)
    expect(page).to have_link("Other AI apps", href: mcp_server_docs_path)
    expect(page).to have_content("Write a year-in-review of my 2026 journal")
    expect(page).to have_link("Export your 2026 entries")

    expect(page.text).not_to include("MCP")
    expect(page).not_to have_content("Ask AI")
  end

  it "asks for a passkey or two-factor authentication first when neither is set up" do
    visit review_path(2026)

    expect(page).to have_link("passkey or two-factor authentication", href: security_path)
  end

  it "skips the security step once two-factor authentication is on" do
    paid_user.generate_otp_secret
    paid_user.update!(otp_enabled: true, otp_enabled_on: Time.current)

    visit review_path(2026)

    expect(page).not_to have_link("passkey or two-factor authentication")
  end
end
