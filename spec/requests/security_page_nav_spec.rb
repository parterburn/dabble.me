# frozen_string_literal: true

require "rails_helper"

# The jump links at the top of Account Security, with a count beside each list that has something in it.
RSpec.describe "Account Security section links", type: :request do
  let(:password) { "correct-horse-battery" }
  let(:user) { create(:user, password: password) }

  before do
    stub_const("WebSessions::TRACKING_STARTED_AT", 1.day.ago)
    https!
    post user_session_path, params: { user: { email: user.email, password: password } },
                            headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Version/18.1 Safari/605.1.15" }
  end

  def nav
    Nokogiri::HTML(response.body).at_css('nav[aria-label="Sections on this page"]')
  end

  def link(anchor)
    nav.at_css(%(a[href="##{anchor}"]))
  end

  it "links to every section, and each anchor exists on the page" do
    get security_path

    page = Nokogiri::HTML(response.body)
    %w[email-password passkeys sessions connected-apps].each do |anchor|
      expect(link(anchor)).to be_present, "no link to ##{anchor}"
      expect(page.at_css("##{anchor}")).to be_present, "no section with id #{anchor}"
    end
  end

  it "counts sessions and connected apps, and shows no count when a list is empty" do
    app = Doorkeeper::Application.create!(name: "Claude", redirect_uri: "https://claude.ai/api/mcp/auth_callback",
                                          scopes: "mcp:access", confidential: false)
    Doorkeeper::AccessToken.create!(application: app, resource_owner_id: user.id, scopes: "mcp:access", expires_in: 1.day.to_i)

    get security_path

    expect(link("sessions").text.squish).to eq("Sessions 1")
    expect(link("connected-apps").text.squish).to eq("Connected apps 1")
    expect(link("passkeys").text.squish).to eq("Passkeys")
  end
end
