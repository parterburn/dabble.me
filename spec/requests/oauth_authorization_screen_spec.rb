# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth authorization screen", type: :request do
  let(:user) { create(:user) }
  let(:code_verifier) { "a" * 64 }
  let(:code_challenge) do
    Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
  end

  def create_application(name, redirect_uri: "https://example.com/callback")
    Doorkeeper::Application.create!(
      name: name,
      redirect_uri: redirect_uri,
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
    it "renders the consent screen with the #{logo[:alt]} brand logo when redirect_uri is on a verified domain" do
      verified_host = logo[:verified_domains].first
      app = create_application(logo[:alt], redirect_uri: "https://#{verified_host}/callback")
      get_consent_screen(app)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ActionController::Base.helpers.image_path(logo[:asset]))
      expect(response.body).to include(verified_host)
      expect(response.body).not_to include("(unverified app)")
    end

    it "does not render the #{logo[:alt]} brand logo when redirect_uri is on an unverified domain" do
      app = create_application(logo[:alt], redirect_uri: "https://attacker.example/callback")
      get_consent_screen(app)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(ActionController::Base.helpers.image_path(logo[:asset]))
      expect(response.body).to include("attacker.example")
      expect(response.body).to include("(unverified app)")
    end
  end

  it "renders the OpenAI logo for Codex when redirect_uri is on a verified OpenAI domain" do
    get_consent_screen(create_application("Codex", redirect_uri: "https://chatgpt.com/callback"))

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(ActionController::Base.helpers.image_path("oauth/openai.png"))
  end

  it "renders the consent screen with initials for an unrecognized client" do
    get_consent_screen(create_application("MCP Inspector"))

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("mi")
    expect(response.body).to include("example.com")
    expect(response.body).to include("(unverified app)")
  end

  describe "approving the consent screen" do
    include ActiveJob::TestHelper

    def approve(application)
      post oauth_authorization_path, params: {
        response_type: "code",
        client_id: application.uid,
        redirect_uri: application.redirect_uri,
        scope: "mcp:access",
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }
    end

    it "emails the user when a new app is connected" do
      app = create_application("MCP Inspector")

      expect { approve(app) }
        .to have_enqueued_mail(UserMailer, :oauth_app_connected)
        .with(user, "MCP Inspector", redirect_host: "example.com", verified: false)
      expect(response).to redirect_to(a_string_starting_with("https://example.com/callback?code="))
    end

    it "does not email again when an already-connected app re-authorizes" do
      app = create_application("MCP Inspector")
      Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application_id: app.id, scopes: "mcp:access", expires_in: 1.day)

      expect { approve(app) }.not_to have_enqueued_mail(UserMailer, :oauth_app_connected)
    end

    it "emails again after the app was removed from Connected apps" do
      app = create_application("MCP Inspector")
      Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application_id: app.id, scopes: "mcp:access", expires_in: 1.day, revoked_at: 1.minute.ago)

      expect { approve(app) }.to have_enqueued_mail(UserMailer, :oauth_app_connected)
    end

    it "does not email the user when the iOS app signs in" do
      app = MobileApp.ensure_application!

      expect {
        get oauth_authorization_path(
          response_type: "code",
          client_id: app.uid,
          redirect_uri: MobileApp::REDIRECT_URI,
          scope: MobileApp::SCOPE,
          code_challenge: code_challenge,
          code_challenge_method: "S256"
        )
      }.not_to have_enqueued_mail(UserMailer, :oauth_app_connected)
      expect(response).to redirect_to(a_string_starting_with("#{MobileApp::REDIRECT_URI}?code="))
    end
  end

  it "rejects DCR registration with javascript: or non-https redirect_uri schemes" do
    post "/oauth/registrations",
      params: { client_name: "Evil", redirect_uris: ["javascript://x/%0aalert(1)"] },
      as: :json
    expect(response).to have_http_status(:bad_request)

    post "/oauth/registrations",
      params: { client_name: "Evil HTTP", redirect_uris: ["http://evil.example/cb"] },
      as: :json
    expect(response).to have_http_status(:bad_request)

    post "/oauth/registrations",
      params: { client_name: "Local Inspector", redirect_uris: ["http://127.0.0.1/cb"] },
      as: :json
    expect(response).to have_http_status(:created)
  end
end
