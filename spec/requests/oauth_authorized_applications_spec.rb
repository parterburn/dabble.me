# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth authorized applications", type: :request do
  let(:user) { create(:user) }

  it "redirects the index to security settings when signed in" do
    sign_in user

    get oauth_authorized_applications_path

    expect(response).to redirect_to(security_path)
  end

  it "doesn't route Doorkeeper's client admin screens (admins use /admin/oauth)" do
    sign_in create(:user, admin: true)

    expect { get "/oauth/applications" }.to raise_error(ActionController::RoutingError)
    expect { get "/oauth/applications/new" }.to raise_error(ActionController::RoutingError)
  end

  it "redirects legacy /settings/mcp to the dedicated MCP documentation" do
    sign_in user
    get "/settings/mcp"
    expect(response).to redirect_to(a_string_ending_with("/mcp-server"))
  end

  it "shows when each connected app was last used and flags ones unused for a year" do
    sign_in user
    stale = Doorkeeper::Application.create!(name: "Old Claude", redirect_uri: "https://claude.ai/api/mcp/auth_callback",
                                            scopes: "mcp:access", confidential: false, created_at: 2.years.ago)
    Doorkeeper::AccessToken.create!(application: stale, resource_owner_id: user.id, scopes: "mcp:access",
                                    expires_in: 1.day.to_i, created_at: Time.zone.parse("2025-03-04"))

    get security_path

    expect(response.body).to include("Old Claude", "Last used Mar 04, 2025", "Not used in over a year")
  end
end
