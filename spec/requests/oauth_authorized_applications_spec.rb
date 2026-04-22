# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth authorized applications", type: :request do
  let(:user) { create(:user) }

  it "redirects the index to MCP settings when signed in" do
    sign_in user

    get oauth_authorized_applications_path

    expect(response).to redirect_to(settings_mcp_path)
  end
end
