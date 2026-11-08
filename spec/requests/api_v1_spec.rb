# frozen_string_literal: true

require "rails_helper"

RSpec.describe "iOS app API (/api/v1)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:free_user) { create(:user) }
  let(:pro_user) { create(:user, plan: "PRO Monthly") }
  let(:mobile_app) { MobileApp.ensure_application! }

  def token_for(user, application: mobile_app, scopes: MobileApp::SCOPE)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id, scopes: scopes).plaintext_token
  end

  def auth(user)
    { "Authorization" => "Bearer #{token_for(user)}" }
  end

  def json
    JSON.parse(response.body)
  end

  describe "authentication" do
    it "rejects requests without a token" do
      get "/api/v1/me"
      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]).to eq("unauthorized")
    end

    it "rejects MCP tokens" do
      mcp_app = Doorkeeper::Application.create!(name: "Claude", redirect_uri: "https://claude.ai/callback", confidential: false, scopes: "mcp:access")
      get "/api/v1/me", headers: { "Authorization" => "Bearer #{token_for(pro_user, application: mcp_app, scopes: 'mcp:access')}" }
      expect(response).to have_http_status(:forbidden)
    end

    it "does not let app tokens call the MCP endpoint" do
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                   headers: auth(pro_user).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:forbidden)
    end

    it "blocks accounts pending deletion" do
      free_user.update_column(:deleted_at, Time.current)
      get "/api/v1/me", headers: auth(free_user)
      expect(response).to have_http_status(:forbidden)
      expect(json["error"]).to eq("account_pending_deletion")
    end
  end

  describe "GET /api/v1/me" do
    it "describes a free account" do
      get "/api/v1/me", headers: auth(free_user)
      expect(response).to have_http_status(:ok)
      expect(json).to include("email" => free_user.email, "plan" => "free", "can_write" => true,
                              "can_add_photos" => false, "can_edit" => false, "can_search" => false)
      expect(json["today"]).to match(/\A\d{4}-\d{2}-\d{2}\z/)
    end

    it "describes a PRO account" do
      get "/api/v1/me", headers: auth(pro_user)
      expect(json).to include("plan" => "pro", "can_write" => true, "can_add_photos" => true, "can_edit" => true, "can_search" => true)
    end

    it "includes the Claude and ChatGPT connector links and what's still needed to use them" do
      get "/api/v1/me", headers: auth(free_user)
      expect(json["ai_connectors"]).to include(
        "claude_url" => ApplicationHelper.claude_plugin_directory_url,
        "chatgpt_url" => ApplicationHelper.chatgpt_plugin_directory_url,
        "requires_pro" => true,
        "requires_security_setup" => true
      )
      create(:webauthn_credential, user: pro_user)
      get "/api/v1/me", headers: auth(pro_user)
      expect(json["ai_connectors"]).to include("requires_pro" => false, "requires_security_setup" => false)
    end
  end

  describe "reading entries" do
    let!(:mine) { create(:entry, user: free_user, date: Time.zone.local(2025, 3, 4), body: "<p>Hello <b>there</b> #coffee</p>") }
    let!(:older) { create(:entry, user: free_user, date: Time.zone.local(2024, 1, 2), body: "<p>Older</p>") }
    let!(:theirs) { create(:entry, user: pro_user, body: "<p>Not yours</p>") }

    it "lists only the user's entries, newest first, for free users too" do
      get "/api/v1/entries", headers: auth(free_user)
      expect(response).to have_http_status(:ok)
      expect(json["entries"].map { |e| e["id"] }).to eq([mine.id, older.id])
      expect(json["entries"].first).to include("date" => "2025-03-04", "hashtags" => ["coffee"])
      expect(json).to include("page" => 1, "next_page" => nil, "total_count" => 2)
    end

    it "paginates" do
      get "/api/v1/entries", params: { per: 1 }, headers: auth(free_user)
      expect(json["entries"].size).to eq(1)
      expect(json["next_page"]).to eq(2)
    end

    it "filters by year and month" do
      get "/api/v1/entries", params: { year: 2024, month: 1 }, headers: auth(free_user)
      expect(json["entries"].map { |e| e["id"] }).to eq([older.id])
    end

    it "rejects a malformed year" do
      get "/api/v1/entries", params: { year: "abc" }, headers: auth(free_user)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "shows a single entry with text body" do
      get "/api/v1/entries/#{mine.id}", headers: auth(free_user)
      expect(response).to have_http_status(:ok)
      expect(json["entry"]["body_text"]).to include("Hello")
      expect(json["entry"]["web_url"]).to end_with("/entries/2025/3/4")
    end

    it "does not show other users' entries" do
      get "/api/v1/entries/#{theirs.id}", headers: auth(free_user)
      expect(response).to have_http_status(:not_found)
    end

    it "returns a random entry" do
      get "/api/v1/entries/random", headers: auth(free_user)
      expect(response).to have_http_status(:ok)
      expect([mine.id, older.id]).to include(json["entry"]["id"])
    end
  end

  describe "day navigation, months and today" do
    let!(:older) { create(:entry, user: pro_user, date: Time.zone.local(2024, 6, 3), body: "<p>June</p>") }
    let!(:middle) { create(:entry, user: pro_user, date: Time.zone.local(2024, 6, 20), body: "<p>Later June</p>") }
    let!(:newer) { create(:entry, user: pro_user, date: Time.zone.local(2025, 1, 2), body: "<p>New year</p>") }

    it "includes the previous and next entries by date" do
      get "/api/v1/entries/#{middle.id}", headers: auth(pro_user)
      expect(json["entry"]["previous_entry"]).to eq("id" => older.id, "date" => "2024-06-03")
      expect(json["entry"]["next_entry"]).to eq("id" => newer.id, "date" => "2025-01-02")

      get "/api/v1/entries/#{newer.id}", headers: auth(pro_user)
      expect(json["entry"]["next_entry"]).to be_nil
    end

    it "lists months with entry counts, newest first" do
      get "/api/v1/entries/months", headers: auth(pro_user)
      expect(json["months"]).to eq([
        { "year" => 2025, "month" => 1, "count" => 1 },
        { "year" => 2024, "month" => 6, "count" => 2 }
      ])
    end

    it "summarizes today: today's entry, On This Day with years ago, and a prompt" do
      Inspiration.create!(category: "Question", body: "What surprised you today?")
      travel_to Time.find_zone(pro_user.send_timezone).local(2026, 6, 20, 12) do
        todays = create(:entry, user: pro_user, date: Date.new(2026, 6, 20).to_s, body: "<p>Today</p>")
        get "/api/v1/today", headers: auth(pro_user)
        expect(json["date"]).to eq("2026-06-20")
        expect(json["entry"]["id"]).to eq(todays.id)
        expect(json["on_this_day"].map { |e| [e["id"], e["years_ago"]] }).to eq([[middle.id, 2]])
        expect(json["on_this_day_available"]).to be(true)
        expect(json["prompt"]).to eq("What surprised you today?")
        expect(json["current_streak"]).to eq(1)
      end
    end

    it "lists upcoming days that have memories, with counts and no entry text" do
      travel_to Time.find_zone(pro_user.send_timezone).local(2026, 6, 18, 12) do
        get "/api/v1/entries/memory_days", params: { days: 5 }, headers: auth(pro_user)
        # middle (2024-06-20) falls on June 20, two days out; older (June 3) is outside the window.
        expect(json["days"]).to eq([{ "date" => "2026-06-20", "count" => 1, "first_year" => 2024 }])
      end

      get "/api/v1/entries/memory_days", headers: auth(free_user)
      expect(response).to have_http_status(:forbidden)
    end

    it "keeps On This Day for PRO on the Today endpoint" do
      create(:entry, user: free_user, date: 1.year.ago, body: "<p>Last year</p>")
      get "/api/v1/today", headers: auth(free_user)
      expect(json).to include("on_this_day" => [], "on_this_day_available" => false, "entry" => nil)
    end
  end

  describe "document" do
    it "is included for entries the app can edit, and nil otherwise" do
      editable = create(:entry, user: pro_user, body: "<p>Hi <b>there</b></p>")
      web_only = create(:entry, user: pro_user, body: "<div data-content='dabblemegpt'>ai</div>")
      expect(Api::EntrySerializer.full(editable)[:document]).to eq([
        { "type" => "paragraph", "runs" => [{ "text" => "Hi " }, { "text" => "there", "bold" => true }] }
      ])
      expect(Api::EntrySerializer.full(web_only)[:document]).to be_nil
    end
  end

  describe "writing entries" do
    it "lets free accounts write text entries but not add photos" do
      post "/api/v1/entries", params: { date: "2026-01-02", body: "Hi" }, headers: auth(free_user)
      expect(response).to have_http_status(:created)
      expect(free_user.entries.count).to eq(1)

      key = "#{Mcp::PresignedImageUpload.key_prefix_for(free_user)}x.jpg"
      post "/api/v1/entries", params: { date: "2026-01-03", body: "Pic", uploaded_image_keys: [key] }, headers: auth(free_user), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(json["error"]).to eq("pro_required")
      expect(free_user.entries.count).to eq(1)

      post "/api/v1/image_uploads", params: { photos: [{ filename: "p.jpg", content_type: "image/jpeg" }] }, headers: auth(free_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "creates an entry, then merges a second one on the same day" do
      post "/api/v1/entries", params: { date: "2026-01-02", body: "First" }, headers: auth(pro_user)
      expect(response).to have_http_status(:created)
      expect(json["entry"]).to include("date" => "2026-01-02")
      expect(json["entry"]["document"]).to eq([{ "type" => "paragraph", "runs" => [{ "text" => "First" }] }])

      post "/api/v1/entries", params: { date: "2026-01-02", body: "Second" }, headers: auth(pro_user)
      expect(response).to have_http_status(:ok)
      expect(json["merged"]).to be(true)
      expect(pro_user.entries.count).to eq(1)
      expect(pro_user.entries.first.body).to include("<hr>")
    end

    it "keeps the journal day for users east of UTC" do
      pro_user.update!(send_timezone: "Tokyo")
      post "/api/v1/entries", params: { date: "2026-11-08", body: "Konbanwa" }, headers: auth(pro_user)
      expect(json["entry"]["date"]).to eq("2026-11-08")

      get "/api/v1/entries", params: { year: 2026, month: 11 }, headers: auth(pro_user)
      expect(json["entries"].map { |e| e["date"] }).to eq(["2026-11-08"])

      post "/api/v1/entries", params: { date: "2026-11-08", body: "Again" }, headers: auth(pro_user)
      expect(json["merged"]).to be(true)
    end

    it "creates a formatted entry from a document" do
      document = [
        { type: "paragraph", runs: [{ text: "Great " }, { text: "hike", bold: true }] },
        { type: "bullet", runs: [{ text: "Trail", link: "https://alltrails.test/x" }] }
      ]
      post "/api/v1/entries", params: { date: "2026-01-03", document: document }, headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:created)
      expect(pro_user.entries.first.body).to eq(
        "<p>Great <strong>hike</strong></p>\n<ul>\n" +
        %(<li><a href="https://alltrails.test/x" target="_blank">Trail</a></li>\n</ul>)
      )
    end

    it "rejects a malformed document" do
      post "/api/v1/entries", params: { date: "2026-01-03", document: [{ type: "script" }] }, headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("invalid_document")
      expect(pro_user.entries.count).to eq(0)
    end

    it "rejects a blank entry" do
      post "/api/v1/entries", params: { date: "2026-01-02", body: " " }, headers: auth(pro_user)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "updates a formatted entry" do
      entry = create(:entry, user: pro_user, body: "<div>Old <b>bold</b></div><div><br></div><div>more</div>")
      document = [{ type: "paragraph", runs: [{ text: "New " }, { text: "bold", bold: true }] }]
      patch "/api/v1/entries/#{entry.id}", params: { document: document }, headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:ok)
      expect(entry.reload.body).to eq("<p>New <strong>bold</strong></p>")
      expect(json["entry"]["document"]).to eq([
        { "type" => "paragraph", "runs" => [{ "text" => "New " }, { "text" => "bold", "bold" => true }] }
      ])
    end

    it "refuses an empty document" do
      entry = create(:entry, user: pro_user, body: "<p>Old</p>")
      patch "/api/v1/entries/#{entry.id}", params: { document: [{ type: "paragraph", runs: [{ text: " " }] }] },
                                           headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(entry.reload.body).to eq("<p>Old</p>")
    end

    it "refuses to edit entries with formatting the app can't represent" do
      entry = create(:entry, user: pro_user, body: %(<p><span style="color:red">Red</span></p>))
      patch "/api/v1/entries/#{entry.id}", params: { document: [{ type: "paragraph", runs: [{ text: "Flat" }] }] },
                                           headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to eq("not_editable")
      expect(entry.reload.body).to eq(%(<p><span style="color:red">Red</span></p>))
    end

    it "requires PRO to edit or delete" do
      entry = create(:entry, user: free_user, body: "<p>Mine</p>")
      patch "/api/v1/entries/#{entry.id}", params: { document: [{ type: "paragraph", runs: [{ text: "x" }] }] },
                                           headers: auth(free_user), as: :json
      expect(response).to have_http_status(:forbidden)
      delete "/api/v1/entries/#{entry.id}", headers: auth(free_user)
      expect(response).to have_http_status(:forbidden)
      expect(entry.reload.body).to eq("<p>Mine</p>")
    end

    it "deletes an entry" do
      entry = create(:entry, user: pro_user, body: "<p>Bye</p>")
      delete "/api/v1/entries/#{entry.id}", headers: auth(pro_user)
      expect(response).to have_http_status(:no_content)
      expect(Entry.exists?(entry.id)).to be(false)
    end

    it "cannot delete another user's entry" do
      entry = create(:entry, user: free_user, body: "<p>Not yours</p>")
      delete "/api/v1/entries/#{entry.id}", headers: auth(pro_user)
      expect(response).to have_http_status(:not_found)
      expect(Entry.exists?(entry.id)).to be(true)
    end
  end

  describe "photos" do
    # Same stubbing as spec/controllers/entries_controller_update_image_spec.rb: a stored photo without S3.
    def give_photo(entry)
      entry.update_column(:image, "existing.jpg")
      allow_any_instance_of(ImageUploader).to receive(:blank?).and_return(false)
      allow_any_instance_of(ImageUploader).to receive(:file).and_return(
        instance_double(CarrierWave::Storage::Fog::File, content_type: "image/jpeg", filename: "existing.jpg",
                                                         path: "uploads/existing.jpg", empty?: false, exists?: true, size: 10)
      )
    end

    it "lists only entries with photos when asked" do
      with_photo = create(:entry, user: pro_user, date: Time.zone.local(2025, 2, 2), body: "<p>Beach</p>")
      create(:entry, user: pro_user, date: Time.zone.local(2025, 2, 3), body: "<p>No photo</p>")
      give_photo(with_photo)
      get "/api/v1/entries", params: { photos: 1 }, headers: auth(pro_user)
      expect(json["entries"].map { |e| e["id"] }).to eq([with_photo.id])
    end

    def photo_key(user, name = SecureRandom.hex(4))
      "#{Mcp::PresignedImageUpload.key_prefix_for(user)}#{name}.jpg"
    end

    before do
      pro_user.update_column(:user_key, "pro-user-key") # stored photo paths include it
      allow(ProcessEntryImageJob).to receive(:perform_later)
      allow(ImageCollageJob).to receive(:perform_later)
    end

    it "presigns several uploads at once" do
      post "/api/v1/image_uploads", params: { photos: Array.new(3) { { filename: "photo.jpg", content_type: "image/jpeg" } } },
                                    headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:created)
      expect(json["uploads"].size).to eq(3)
      expect(json["uploads"].map { |u| u["uploaded_image_key"] }.uniq.size).to eq(3)
      expect(json["uploads"].first).to include("upload_method" => "PUT")
    end

    it "limits presigned uploads to the collage maximum" do
      post "/api/v1/image_uploads", params: { photos: Array.new(9) { { filename: "p.jpg", content_type: "image/jpeg" } } },
                                    headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "processes a single photo directly and shows it as processing right away" do
      key = photo_key(pro_user)
      post "/api/v1/entries", params: { date: "2026-02-01", body: "Pic", uploaded_image_keys: [key] }, headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:created)
      expect(json["entry"]["image_processing"]).to be(true)
      expect(ProcessEntryImageJob).to have_received(:perform_later).with(json["entry"]["id"], key)
      expect(ImageCollageJob).not_to have_received(:perform_later)
    end

    it "queues a collage for several photos and marks the entry processing before the job runs" do
      keys = Array.new(3) { photo_key(pro_user) }
      expect(ImageCollageJob).to receive(:perform_later) do |entry_id, urls:|
        expect(Entry.find(entry_id).uploading_image?).to be(true)
        expect(urls.size).to eq(3)
        expect(urls).to all(include("/tmp/mcp/"))
      end
      post "/api/v1/entries", params: { date: "2026-02-01", body: "", uploaded_image_keys: keys }, headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:created)
      expect(json["entry"]).to include("image_processing" => true)
      expect(json["entry"]["image_url"]).to eq(Entry::UPLOADING_PLACEHOLDER_URL)
    end

    it "folds new photos into a collage with the day's existing photo" do
      existing = create(:entry, user: pro_user, date: Time.zone.local(2026, 2, 1, 12), body: "<p>Earlier</p>")
      give_photo(existing)
      post "/api/v1/entries", params: { date: "2026-02-01", body: "More", uploaded_image_keys: [photo_key(pro_user)] },
                              headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:ok)
      expect(json["merged"]).to be(true)
      expect(ImageCollageJob).to have_received(:perform_later).with(existing.id, urls: [kind_of(String)])
      expect(existing.reload.uploading_image?).to be(true)
    end

    it "refuses more photos than the collage can hold" do
      post "/api/v1/entries", params: { date: "2026-02-01", body: "x", uploaded_image_keys: Array.new(9) { photo_key(pro_user) } },
                              headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      existing = create(:entry, user: pro_user, date: Time.zone.local(2026, 2, 2, 12), body: "<p>Has photo</p>")
      give_photo(existing)
      post "/api/v1/entries", params: { date: "2026-02-02", body: "x", uploaded_image_keys: Array.new(8) { photo_key(pro_user) } },
                              headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["details"].first).to include("up to 7 more")
      expect(ImageCollageJob).not_to have_received(:perform_later)
    end

    it "rejects keys that belong to someone else" do
      post "/api/v1/entries", params: { date: "2026-02-01", body: "x", uploaded_image_keys: [photo_key(free_user)] },
                              headers: auth(pro_user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(pro_user.entries.count).to eq(0)
    end
  end

  describe "POST /api/v1/account/deletion_request" do
    include ActiveJob::TestHelper

    it "emails a link to the web deletion page without deleting anything, at most once per window" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) # test env uses :null_store
      expect {
        post "/api/v1/account/deletion_request", headers: auth(free_user)
        post "/api/v1/account/deletion_request", headers: auth(free_user)
      }.to have_enqueued_mail(UserMailer, :account_deletion_requested).once
      expect(response).to have_http_status(:accepted)
      expect(json["email"]).to eq(free_user.email)
      expect(free_user.reload.deletion_pending?).to be(false)
    end

    it "builds an email that links to the web deletion page" do
      mail = UserMailer.account_deletion_requested(free_user)
      expect(mail.to).to eq([free_user.email])
      expect(mail.body.encoded).to include("/settings/delete-account")
    end
  end

  describe "excerpt" do
    it "is plain text without Markdown markers, with spaces between blocks" do
      entry = create(:entry, user: pro_user, body: "<p>Made it to <strong>Yosemite</strong> &amp; <em>back</em>.</p><ul><li>one</li><li>two</li></ul>")
      expect(Api::EntrySerializer.summary(entry)[:excerpt]).to eq("Made it to Yosemite & back. one two")
    end
  end

  describe "body_text" do
    it "shows one blank line between email paragraphs" do
      entry = create(:entry, user: pro_user, body: "<div>One.</div><div><br></div><div>Two.</div><div><br></div><div>Three.</div>")
      expect(Api::EntrySerializer.full(entry)[:body_text]).to eq("One.\n\nTwo.\n\nThree.")
    end
  end

  describe "GET /api/v1/stats" do
    it "counts entries, words, streaks, writing days and hashtags for free accounts too" do
      zone = Time.find_zone(free_user.send_timezone)
      travel_to zone.local(2026, 6, 20, 12) do
        create(:entry, user: free_user, date: Time.zone.local(2026, 6, 20), body: "<p>Hiking with <b>Sam</b> #Outside</p>")
        create(:entry, user: free_user, date: Time.zone.local(2026, 6, 19), body: "<p>Rain &amp; tea #outside</p>")
        create(:entry, user: free_user, date: Time.zone.local(2026, 6, 18), body: "<p>#books</p>")
        create(:entry, user: free_user, date: Time.zone.local(2026, 1, 1), body: "<p>One</p><p>two three</p>")
        create(:entry, user: free_user, date: Time.zone.local(2026, 1, 2), body: "<div><br></div>")
        create(:entry, user: pro_user, date: Time.zone.local(2026, 6, 20), body: "<p>Not counted #secret</p>")

        get "/api/v1/stats", headers: auth(free_user)
      end

      expect(response).to have_http_status(:ok)
      expect(json).to include(
        "total_entries" => 5, "total_words" => 11, "current_streak" => 3, "longest_streak" => 3,
        "entries_this_year" => 5, "first_entry_date" => "2026-01-01", "photo_entries" => 0
      )
      expect(json["writing_days"]).to eq(%w[2026-01-01 2026-01-02 2026-06-18 2026-06-19 2026-06-20])
      expect(json["months"].size).to eq(12)
      expect(json["months"].last).to eq("year" => 2026, "month" => 6, "count" => 3)
      expect(json["months"].find { |m| m["month"] == 1 && m["year"] == 2026 }["count"]).to eq(2)
      expect(json["top_hashtags"]).to eq([{ "tag" => "Outside", "count" => 2 }, { "tag" => "books", "count" => 1 }])
    end

    it "keeps a streak going while today is still unwritten" do
      travel_to Time.find_zone(free_user.send_timezone).local(2026, 6, 20, 12) do
        create(:entry, user: free_user, date: Time.zone.local(2026, 6, 19), body: "<p>a</p>")
        create(:entry, user: free_user, date: Time.zone.local(2026, 6, 18), body: "<p>b</p>")
        get "/api/v1/stats", headers: auth(free_user)
      end
      expect(json["current_streak"]).to eq(2)
    end
  end

  describe "GET /api/v1/hashtags" do
    it "requires PRO" do
      get "/api/v1/hashtags", headers: auth(free_user)
      expect(response).to have_http_status(:forbidden)
    end

    it "counts the past year's hashtags, most used first" do
      travel_to Time.find_zone(pro_user.send_timezone).local(2026, 6, 20, 12) do
        create(:entry, user: pro_user, date: Time.zone.local(2026, 6, 1), body: "<p>#family dinner #Cooking</p>")
        create(:entry, user: pro_user, date: Time.zone.local(2026, 5, 1), body: "<p>#family</p>")
        create(:entry, user: pro_user, date: Time.zone.local(2024, 5, 1), body: "<p>#ancient</p>")
        get "/api/v1/hashtags", headers: auth(pro_user)
      end
      expect(json["hashtags"]).to eq([{ "tag" => "family", "count" => 2 }, { "tag" => "Cooking", "count" => 1 }])
    end
  end

  describe "GET /api/v1/search" do
    before do
      create(:entry, user: pro_user, body: "<p>Went hiking today</p>")
      create(:entry, user: pro_user, body: "<p>Rainy</p>")
    end

    it "requires PRO" do
      get "/api/v1/search", params: { q: "hiking" }, headers: auth(free_user)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns matches" do
      get "/api/v1/search", params: { q: "hiking" }, headers: auth(pro_user)
      expect(json["total_count"]).to eq(1)
      expect(json["entries"].first["excerpt"]).to include("hiking")
    end
  end

  describe "OAuth sign-in for the iOS app" do
    let(:code_verifier) { SecureRandom.urlsafe_base64(48) }
    let(:code_challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false) }

    it "skips the consent screen and issues an app:journal token to a free user" do
      sign_in free_user
      get oauth_authorization_path(
        response_type: "code",
        client_id: mobile_app.uid,
        redirect_uri: MobileApp::REDIRECT_URI,
        scope: MobileApp::SCOPE,
        state: "xyz",
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      )
      expect(response).to have_http_status(:redirect)
      location = URI.parse(response.location)
      expect("#{location.scheme}:#{location.path}").to eq(MobileApp::REDIRECT_URI)
      query = Rack::Utils.parse_query(location.query)
      expect(query["state"]).to eq("xyz")

      post oauth_token_path, params: {
        grant_type: "authorization_code",
        code: query["code"],
        client_id: mobile_app.uid,
        redirect_uri: MobileApp::REDIRECT_URI,
        code_verifier: code_verifier
      }
      expect(response).to have_http_status(:ok)
      expect(json["scope"]).to eq(MobileApp::SCOPE)
      expect(json["refresh_token"]).to be_present

      get "/api/v1/me", headers: { "Authorization" => "Bearer #{json['access_token']}" }
      expect(response).to have_http_status(:ok)
    end

    it "sends signed-out users to the login page without a flash, and remembers where to return" do
      authorize_path = oauth_authorization_path(
        response_type: "code", client_id: mobile_app.uid, redirect_uri: MobileApp::REDIRECT_URI,
        scope: MobileApp::SCOPE, state: "xyz", code_challenge: code_challenge, code_challenge_method: "S256"
      )
      get authorize_path
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to be_nil
      expect(session["user_return_to"]).to eq(authorize_path)
    end

    it "opens the sign-up page for prompt=create and returns there after signing up" do
      authorize_path = oauth_authorization_path(
        response_type: "code", client_id: mobile_app.uid, redirect_uri: MobileApp::REDIRECT_URI, scope: MobileApp::SCOPE,
        state: "xyz", code_challenge: code_challenge, code_challenge_method: "S256", prompt: "create"
      )
      get authorize_path
      expect(response).to redirect_to(new_user_registration_path)
      expect(session["user_return_to"]).to eq(authorize_path)
    end

    it "does not let MCP clients register the app's redirect scheme for a different scope" do
      app = Doorkeeper::Application.new(name: "Sneaky", redirect_uri: MobileApp::REDIRECT_URI, confidential: false, scopes: "mcp:access")
      expect(app).to be_valid # scheme is allowed, but the token would still only carry mcp:access
      expect(MobileApp.client?(app)).to be(false)
    end
  end

  describe "token revocation" do
    let(:mcp_app) { Doorkeeper::Application.create!(name: "Claude", redirect_uri: "https://claude.ai/callback", confidential: false, scopes: "mcp:access") }

    it "keeps the app signed in when PRO lapses but revokes MCP" do
      app_token = Doorkeeper::AccessToken.create!(application: mobile_app, resource_owner_id: pro_user.id, scopes: MobileApp::SCOPE)
      mcp_token = Doorkeeper::AccessToken.create!(application: mcp_app, resource_owner_id: pro_user.id, scopes: "mcp:access")

      pro_user.update!(plan: "Free")

      expect(app_token.reload.revoked_at).to be_nil
      expect(mcp_token.reload.revoked_at).to be_present
    end

    it "signs the app out when the password changes" do
      app_token = Doorkeeper::AccessToken.create!(application: mobile_app, resource_owner_id: free_user.id, scopes: MobileApp::SCOPE)
      free_user.update!(password: "a-brand-new-password-123")
      expect(app_token.reload.revoked_at).to be_present
    end
  end
end
