# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth authorized applications", type: :request do
  let(:user) { create(:user) }

  it "redirects the index to security settings when signed in" do
    sign_in user

    get oauth_authorized_applications_path

    expect(response).to redirect_to(security_path)
  end

  it "redirects legacy /settings/mcp to Support MCP FAQ" do
    sign_in user
    get "/settings/mcp"
    expect(response).to redirect_to(a_string_ending_with("/support#mcp"))
  end
end
