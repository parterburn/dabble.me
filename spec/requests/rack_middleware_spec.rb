# frozen_string_literal: true

require "rails_helper"

# Covers the Rack-level middleware in config/application.rb: the bad-request
# guard (malformed bodies/params become a 400, not a 500) and rack-affiliates.
RSpec.describe "Rack middleware", type: :request do
  def set_cookie_header
    Array(response.headers["set-cookie"]).join("\n")
  end

  describe "bad request guard" do
    it "returns 400 for a truncated multipart body" do
      post "/", params: "--abc123\r\ncontent-disposition: form-data; name=\"x\"\r\n\r\nval",
                headers: { "CONTENT_TYPE" => "multipart/form-data; boundary=abc123" }

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("EmptyContentError")
    end

    it "returns 400 for a multipart boundary that is too long" do
      post "/", params: "--#{'a' * 80}\r\n", headers: { "CONTENT_TYPE" => "multipart/form-data; boundary=#{'a' * 80}" }

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("BoundaryTooLongError")
    end

    it "returns 400 for conflicting parameter types" do
      get "/?entry=1&entry[body]=2"

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("text/plain")
    end
  end

  describe "rack-affiliates" do
    it "stores the ?ref= tag in a cookie" do
      get "/?ref=friend"

      expect(set_cookie_header).to match(/^aff_tag=friend;/)
    end

    it "records the referrer on sign-up" do
      password = "correct-horse-battery"
      post "#{user_registration_path}?ref=friend", params: {
        user: { email: "ref-#{SecureRandom.hex(4)}@example.com", password: password, password_confirmation: password }
      }

      expect(User.order(:id).last.referrer).to eq("friend")
    end
  end
end
