require "rails_helper"

RSpec.describe "OAuth MCP metadata", type: :request do
  it "returns protected resource metadata" do
    get "/.well-known/oauth-protected-resource/mcp"

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["resource"]).to end_with("/mcp")
    expect(json["authorization_servers"]).to be_present
    expect(json["scopes_supported"]).to include("mcp:access")
  end

  it "returns authorization server metadata" do
    get "/.well-known/oauth-authorization-server/mcp"

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    %w[issuer authorization_endpoint token_endpoint registration_endpoint].each do |key|
      expect(json[key]).to be_present
    end
    expect(json["scopes_supported"]).to include("mcp:access")
    expect(json["code_challenge_methods_supported"]).to include("S256")
  end
end
