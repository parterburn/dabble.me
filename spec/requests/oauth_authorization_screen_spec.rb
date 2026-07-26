# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth authorization screen", type: :request do
  let(:user) { create(:user) }
  let(:code_verifier) { "a" * 64 }
  let(:code_challenge) do
    Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
  end

  def create_application(name)
    Doorkeeper::Application.create!(
      name: name,
      redirect_uri: "https://example.com/callback",
      confidential: false,
      scopes: "mcp:access"
    )
  end

  def get_consent_screen(application)
    get oauth_authorization_path(
      response_type: "code",
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      scope: "mcp:access",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    )
  end

  before { sign_in user }

  # Brand logos must be linked in app/assets/config/manifest.js; an unlinked
  # asset previously raised AssetNotFound and 500'd the whole consent screen.
  ApplicationHelper::OAUTH_KNOWN_APPLICATION_LOGOS.each do |logo|
    it "renders the consent screen with the #{logo[:alt]} brand logo" do
      get_consent_screen(create_application(logo[:alt]))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ActionController::Base.helpers.image_path(logo[:asset]))
    end
  end

  it "renders the consent screen with initials for an unrecognized client" do
    get_consent_screen(create_application("MCP Inspector"))

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("mi")
  end
end
