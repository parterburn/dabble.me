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
end
