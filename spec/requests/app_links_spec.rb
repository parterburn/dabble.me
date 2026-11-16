# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Universal links for the iOS app", type: :request do
  it "tells iOS which pages the app opens, as JSON and without signing in" do
    get "/.well-known/apple-app-site-association"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    details = JSON.parse(response.body).dig("applinks", "details")
    expect(details.size).to eq(1)
    expect(details.first["appIDs"]).to eq(["B79A4CAS56.me.dabble.ios"])
    paths = details.first["components"].map { |component| component["/"] }
    expect(paths).to include("/entries", "/today", "/entries/new", "/entries/20??/*/*", "/search", "/rewind", "/rewind/*")
    # Pages the app has no screen for stay on the web.
    expect(paths).not_to include("/entries/*", "/*", "/settings")
  end
end
