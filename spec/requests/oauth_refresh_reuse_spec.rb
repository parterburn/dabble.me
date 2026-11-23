# frozen_string_literal: true

require "rails_helper"

# OauthRefreshReuse: a refresh token sent again after it was swapped for a new one.
RSpec.describe "Reusing a rotated refresh token", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:claude) do
    Doorkeeper::Application.create!(name: "Claude", redirect_uri: "https://claude.ai/callback",
                                    confidential: false, scopes: "mcp:access")
  end

  def issue(application: claude, scopes: "mcp:access", user_session_id: nil)
    token = Doorkeeper::AccessToken.create_for(application: application, resource_owner: user, scopes: scopes,
                                               expires_in: 1.day, use_refresh_token: true)
    token.update_columns(user_session_id: user_session_id) if user_session_id
    token
  end

  def refresh(refresh_token, application: claude)
    post oauth_token_path, params: { grant_type: "refresh_token", refresh_token: refresh_token, client_id: application.uid }
    response.parsed_body
  end

  it "only refuses a reuse within the grace window, as a parallel refresh would send" do
    old = issue
    old_refresh = old.plaintext_refresh_token
    fresh = refresh(old_refresh)

    expect {
      refresh(old_refresh)
    }.not_to have_enqueued_mail(UserMailer, :oauth_refresh_token_reused)

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("invalid_grant")
    expect(Doorkeeper::AccessToken.by_token(fresh["access_token"])).not_to be_revoked
  end

  it "after the grace window, cuts off the newer token and emails the user" do
    old = issue
    old_refresh = old.plaintext_refresh_token
    fresh = refresh(old_refresh)

    travel_to(2.minutes.from_now) do
      expect {
        refresh(old_refresh)
      }.to have_enqueued_mail(UserMailer, :oauth_refresh_token_reused)
      expect(response).to have_http_status(:bad_request)
      expect(Doorkeeper::AccessToken.by_token(fresh["access_token"])).to be_revoked

      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "list_entries" } }.to_json,
                   headers: { "Authorization" => "Bearer #{fresh['access_token']}", "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it "does nothing more for a token that was revoked some other way" do
    old = issue
    old_refresh = old.plaintext_refresh_token
    refresh(old_refresh)
    user.revoke_doorkeeper_access_tokens! # e.g. removed in Connected apps, password changed

    travel_to(2.minutes.from_now) do
      expect { refresh(old_refresh) }.not_to have_enqueued_mail(UserMailer, :oauth_refresh_token_reused)
    end
    expect(response).to have_http_status(:bad_request)
  end

  it "follows the chain to the newest token after several refreshes" do
    first = issue
    first_refresh = first.plaintext_refresh_token
    second = refresh(first_refresh)
    third = refresh(second["refresh_token"])

    travel_to(2.minutes.from_now) do
      expect { refresh(first_refresh) }.to have_enqueued_mail(UserMailer, :oauth_refresh_token_reused)
      expect(Doorkeeper::AccessToken.by_token(third["access_token"])).to be_revoked
    end
  end

  it "can't disconnect a connection made after the old one was removed" do
    old = issue
    old_refresh = old.plaintext_refresh_token
    refresh(old_refresh)

    travel_to(1.hour.from_now) do
      user.revoke_doorkeeper_access_tokens! # removed in Connected apps
    end
    travel_to(2.hours.from_now) do
      reconnected = issue
      expect { refresh(old_refresh) }.not_to have_enqueued_mail(UserMailer, :oauth_refresh_token_reused)
      expect(reconnected.reload).not_to be_revoked
    end
  end

  it "leaves the same app on another device alone" do
    mobile_app = MobileApp.ensure_application!
    phone = user.user_sessions.create!(kind: "ios_app", last_active_at: Time.current)
    ipad = user.user_sessions.create!(kind: "ios_app", last_active_at: Time.current)
    old = issue(application: mobile_app, scopes: MobileApp::SCOPE, user_session_id: phone.id)
    old_refresh = old.plaintext_refresh_token
    ipad_token = issue(application: mobile_app, scopes: MobileApp::SCOPE, user_session_id: ipad.id)
    fresh = refresh(old_refresh, application: mobile_app)

    travel_to(2.minutes.from_now) { refresh(old_refresh, application: mobile_app) }

    expect(Doorkeeper::AccessToken.by_token(fresh["access_token"]).revoked_at).to be_present
    expect(ipad_token.reload).not_to be_revoked
  end
end
