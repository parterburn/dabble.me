# frozen_string_literal: true

require "rails_helper"

# The MCP authorization spec's server-side rules: PKCE for every client, exact redirect URIs,
# and RFC 8707 resource indicators naming this server.
RSpec.describe "OAuth rules from the MCP authorization spec", type: :request do
  let(:user) { create(:user) }
  let(:code_verifier) { "v" * 64 }
  let(:code_challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false) }
  let(:application) do
    Doorkeeper::Application.create!(
      name: "MCP client", redirect_uri: "https://client.example/cb", confidential: false, scopes: "mcp:access"
    )
  end
  let(:mcp_resource) { "http://www.example.com/mcp" }

  def authorize_params(**overrides)
    {
      response_type: "code",
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      scope: "mcp:access",
      state: "s1",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }.merge(overrides).compact
  end

  def redirect_query
    Rack::Utils.parse_query(URI.parse(response.location).query)
  end

  describe "the authorization endpoint" do
    before { sign_in user }

    it "shows the consent screen for a request naming this server as the resource" do
      get oauth_authorization_path(authorize_params(resource: mcp_resource))
      expect(response).to have_http_status(:ok)
    end

    it "answers a resource on another server with invalid_target" do
      get oauth_authorization_path(authorize_params(resource: "https://evil.example/mcp"))

      expect(response).to redirect_to(a_string_starting_with("https://client.example/cb?"))
      expect(redirect_query).to include("error" => "invalid_target", "state" => "s1")
      expect(redirect_query).not_to have_key("code")
    end

    it "refuses invalid_target on approval too, without issuing a code" do
      expect {
        post oauth_authorization_path, params: authorize_params(resource: "https://evil.example/mcp")
      }.not_to change(Doorkeeper::AccessGrant, :count)
      expect(redirect_query["error"]).to eq("invalid_target")
    end

    it "renders an error, never redirects, when redirect_uri adds a query to the registered one" do
      get oauth_authorization_path(authorize_params(redirect_uri: "https://client.example/cb?next=https://evil.example"))

      expect(response).to have_http_status(:bad_request)
      expect(response.location).to be_nil
      expect(response.body).to include("redirect uri")
    end

    it "lets a loopback client change port" do
      loopback = Doorkeeper::Application.create!(
        name: "Inspector", redirect_uri: "http://127.0.0.1/cb", confidential: false, scopes: "mcp:access"
      )
      get oauth_authorization_path(authorize_params(client_id: loopback.uid, redirect_uri: "http://127.0.0.1:53111/cb"))
      expect(response).to have_http_status(:ok)
    end

    it "requires PKCE from a public client" do
      get oauth_authorization_path(authorize_params(code_challenge: nil, code_challenge_method: nil))
      expect(redirect_query).to include("error" => "invalid_request")
      expect(redirect_query).not_to have_key("code")
    end

    it "requires PKCE from a confidential client too" do
      confidential = Doorkeeper::Application.create!(
        name: "Admin-made client", redirect_uri: "https://client.example/cb", confidential: true, scopes: "mcp:access"
      )

      expect {
        post oauth_authorization_path,
             params: authorize_params(client_id: confidential.uid, code_challenge: nil, code_challenge_method: nil)
      }.not_to change(Doorkeeper::AccessGrant, :count)
      expect(redirect_query).to include("error" => "invalid_request", "state" => "s1")
    end

    it "refuses the plain PKCE method" do
      expect {
        post oauth_authorization_path, params: authorize_params(code_challenge: code_verifier, code_challenge_method: "plain")
      }.not_to change(Doorkeeper::AccessGrant, :count)
      expect(redirect_query["error"]).to eq("invalid_code_challenge_method")
    end
  end

  it "refuses a foreign resource before sending the user to sign in" do
    get oauth_authorization_path(authorize_params(resource: "https://evil.example/mcp"))
    expect(redirect_query["error"]).to eq("invalid_target")
  end

  describe "the token endpoint" do
    def issue_code
      sign_in user
      post oauth_authorization_path, params: authorize_params(resource: mcp_resource)
      redirect_query.fetch("code")
    end

    def exchange(code, **overrides)
      post oauth_token_path, params: {
        grant_type: "authorization_code",
        code: code,
        client_id: application.uid,
        redirect_uri: application.redirect_uri,
        code_verifier: code_verifier,
        resource: mcp_resource
      }.merge(overrides).compact
    end

    it "issues a token for this server's resource" do
      exchange(issue_code)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("access_token", "refresh_token")
    end

    it "answers a token request for another resource with invalid_target and burns nothing" do
      code = issue_code
      exchange(code, resource: "https://evil.example/mcp")

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_target")
      expect(response.headers["Cache-Control"]).to include("no-store")

      exchange(code)
      expect(response).to have_http_status(:ok)
    end

    it "refuses a code exchanged without its PKCE verifier" do
      exchange(issue_code, code_verifier: nil)
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_request")
    end

    it "refuses a refresh that names another resource" do
      exchange(issue_code)
      refresh = JSON.parse(response.body).fetch("refresh_token")

      post oauth_token_path, params: {
        grant_type: "refresh_token", refresh_token: refresh, client_id: application.uid, resource: "https://evil.example"
      }
      expect(JSON.parse(response.body)["error"]).to eq("invalid_target")
    end
  end
end
