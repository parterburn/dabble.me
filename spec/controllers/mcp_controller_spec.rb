require "rails_helper"

RSpec.describe McpController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers
  include_context "has all objects"

  def doorkeeper_plain_token_for(user)
    app = Doorkeeper::Application.find_or_create_by!(uid: "rspec-mcp-client") do |a|
      a.name = "RSpec MCP"
      a.redirect_uri = "http://127.0.0.1/cb"
      a.scopes = "mcp:access"
      a.confidential = false
    end
    rec = Doorkeeper::AccessToken.create!(
      resource_owner_id: user.id,
      application_id: app.id,
      scopes: "mcp:access",
      expires_in: 2.hours
    )
    rec.plaintext_token
  end

  describe "invoke" do
    context "without a valid OAuth token" do
      it "returns unauthorized" do
        post :invoke, params: { jsonrpc: "2.0", id: 1, method: "initialize" }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with a valid Doorkeeper token" do
      let(:token) { doorkeeper_plain_token_for(paid_user) }

      before do
        paid_user.generate_otp_secret
        paid_user.update!(otp_enabled: true, otp_enabled_on: Time.current)
        request.env["HTTP_AUTHORIZATION"] = "Bearer #{token}"
      end

      it "rejects GET with 405" do
        get :invoke, as: :json
        expect(response).to have_http_status(:method_not_allowed)
      end

      it "initializes the MCP server" do
        post :invoke, params: { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig("result", "serverInfo", "name")).to eq("dabble-me")
        instructions = body.dig("result", "instructions").to_s
        expect(instructions).to include("/entries/YYYY/M/D").and include("/write")
      end

      it "searches only the authenticated user entries" do
        paid_entry.update!(body: "I saw the northern lights in Iceland #travel")
        not_my_entry.update!(body: "I saw the northern lights too #travel")

        post :invoke, params: {
          jsonrpc: "2.0",
          id: 2,
          method: "tools/call",
          params: {
            name: "search_entries",
            arguments: { query: "northern lights" }
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body).not_to have_key("error")
        entries = body.dig("result", "structuredContent", "entries")
        expect(entries.length).to eq(1)
        expect(entries.first["id"]).to eq(paid_entry.id)
        expect(entries.first["excerpt"]).to include("northern lights")
      end

      it "returns aggregate analysis" do
        paid_entry.update!(body: "First #gratitude note")
        paid_user.entries.create!(body: "Second #gratitude note", date: 1.day.ago)

        post :invoke, params: {
          jsonrpc: "2.0",
          id: 3,
          method: "tools/call",
          params: {
            name: "analyze_entries",
            arguments: {}
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        structured = body.dig("result", "structuredContent")
        expect(structured["total_entries"]).to eq(2)
        expect(structured["top_hashtags"].first).to include("hashtag" => "gratitude", "count" => 2)
      end

      it "defaults date to today in the user timezone when omitted" do
        expected_url = Mcp::Tools::Helpers.entry_public_url(Date.new(2030, 1, 15))

        denver = ActiveSupport::TimeZone["America/Denver"]
        travel_to denver.local(2030, 1, 15, 14, 0, 0) do
          paid_user.update!(send_timezone: "America/Denver")
          paid_user.entries.delete_all
          fresh = doorkeeper_plain_token_for(paid_user)
          request.env["HTTP_AUTHORIZATION"] = "Bearer #{fresh}"

          post :invoke, params: {
            jsonrpc: "2.0",
            id: 35,
            method: "tools/call",
            params: {
              name: "create_entry",
              arguments: { "body" => "Today entry without date param" }
            }
          }, as: :json
        end

        expect(response).to have_http_status(:ok)
        structured = JSON.parse(response.body).dig("result", "structuredContent")
        expect(structured["success"]).to eq(true)
        expect(structured["entry"]["date"]).to eq("2030-01-15")
        expect(structured["entry"]["url"]).to eq(expected_url)
      end

      it "creates a new entry on an unused date" do
        expected_url = Mcp::Tools::Helpers.entry_public_url(Date.new(2099, 6, 15))

        post :invoke, params: {
          jsonrpc: "2.0",
          id: 31,
          method: "tools/call",
          params: {
            name: "create_entry",
            arguments: {
              "date" => "2099-06-15",
              "body" => "Line one.\n\nLine two with #mcp"
            }
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        structured = body.dig("result", "structuredContent")
        expect(structured["success"]).to eq(true)
        expect(structured["merged"]).to eq(false)
        expect(structured["entry"]["date"]).to eq("2099-06-15")
        expect(structured["entry"]["url"]).to eq(expected_url)

        created = paid_user.entries.find(structured["entry"]["id"])
        expect(created.body).to include("<p>Line one.</p>")
      end

      it "returns a direct image upload URL" do
        post :invoke, params: {
          jsonrpc: "2.0",
          id: 32,
          method: "tools/call",
          params: {
            name: "get_image_upload_url",
            arguments: {
              "filename" => "journal-photo.png",
              "content_type" => "image/png"
            }
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        structured = JSON.parse(response.body).dig("result", "structuredContent")
        expect(structured["success"]).to eq(true)
        expect(structured["upload_method"]).to eq("PUT")
        expect(structured["upload_url"]).to include("X-Amz-Signature")
        expect(structured["uploaded_image_key"]).to start_with(Mcp::PresignedImageUpload.key_prefix_for(paid_user))
        expect(structured["upload_headers"]).to include("Content-Type" => "image/png")
      end

      it "rejects direct image upload URLs for accounts without journal access" do
        free_token = doorkeeper_plain_token_for(free_ai)
        request.env["HTTP_AUTHORIZATION"] = "Bearer #{free_token}"

        post :invoke, params: {
          jsonrpc: "2.0",
          id: 33,
          method: "tools/call",
          params: {
            name: "get_image_upload_url",
            arguments: {
              "filename" => "journal-photo.png",
              "content_type" => "image/png"
            }
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).dig("result", "isError")).to eq(true)
      end

      it "scopes tools to server_context user, not another user id in memory" do
        paid_entry.update!(body: "secret paid content")
        other = free_ai

        post :invoke, params: {
          jsonrpc: "2.0",
          id: 99,
          method: "tools/call",
          params: {
            name: "search_entries",
            arguments: { query: "secret paid" }
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        entries = JSON.parse(response.body).dig("result", "structuredContent", "entries")
        expect(entries.map { |e| e["id"] }).to eq([paid_entry.id])
        expect(free_ai.entries.where(id: paid_entry.id)).to be_empty
      end
    end

    context "when the user loses strong auth after OAuth (token still valid)" do
      let(:token) { doorkeeper_plain_token_for(paid_user) }

      before do
        paid_user.generate_otp_secret
        paid_user.update!(otp_enabled: true, otp_enabled_on: Time.current)
        request.env["HTTP_AUTHORIZATION"] = "Bearer #{token}"
      end

      it "returns a tool error for journal operations",
         skip: "MCP strong-auth gate temporarily off during Claude/ChatGPT connector review" do
        paid_user.update!(otp_enabled: false)

        post :invoke, params: {
          jsonrpc: "2.0",
          id: 4,
          method: "tools/call",
          params: {
            name: "search_entries",
            arguments: { query: "x" }
          }
        }, as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body.dig("result", "isError")).to eq(true)
      end
    end
  end
end
