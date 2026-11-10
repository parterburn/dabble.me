require "rails_helper"

RSpec.describe "Yearly Rewind page", type: :request do
  include_context "has all objects"

  describe "old /review links" do
    it "forward permanently to /rewind" do
      get "/review/2025"
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to("/rewind/2025")

      get "/review"
      expect(response).to redirect_to("/rewind")
    end

    it "drop anything that isn't a year" do
      get "/review/javascript:alert(1)"
      expect(response).to redirect_to("/rewind")
    end
  end

  describe "GET /rewind/:year" do
    before do
      # Not paid_user.entries.destroy_all: that caches an empty association
      # on the very object the request then signs in as.
      Entry.where(user: paid_user).destroy_all
      [Date.new(2026, 3, 1), Date.new(2026, 3, 2), Date.new(2026, 3, 3), Date.new(2026, 3, 10)].each do |date|
        create(:entry, user: paid_user, date: date, body: "Wrote today")
      end
      create(:entry, user: paid_user, date: Date.new(2025, 12, 30), body: "Last year")
      create(:entry, user: paid_user, date: Date.new(2025, 12, 31), body: "Last year")
      sign_in paid_user
    end

    it "is called the year's Rewind and shows that year's longest streak" do
      get "/rewind/2026"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<title>2026 Rewind — Dabble me.</title>")
      page = Capybara.string(response.body)
      expect(page).to have_css("h3", text: "2026 Rewind")
      expect(page).to have_link("2025", href: "/rewind/2025")
      # Mar 1-3 in a row; the Dec 30-31 run belongs to 2025.
      expect(page).to have_content(/of the days in 2026 with entries\s+• 3 days is your longest streak/)
      expect(response.body).not_to match(/Year in Review/i)
    end

    it "leaves the streak out when no two days are in a row" do
      paid_user.entries.where(date: [Date.new(2026, 3, 2), Date.new(2026, 3, 3)]).delete_all

      get "/rewind/2026"

      expect(Capybara.string(response.body)).to have_content("of the days in 2026 with entries")
      expect(response.body).not_to include("longest streak")
    end
  end
end
