# frozen_string_literal: true

require "rails_helper"

# iOS 26 and later blur the top of a Home Screen web app unless a solid bar is
# fixed to the top edge, so the navbar stays pinned and solid there on phones.
RSpec.describe "Navbar in a Home Screen web app", type: :feature, js: true do
  include_context "has all objects"

  def on_phone
    page.current_window.resize_to(390, 844)
    yield
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  # navigator.standalone is true when iOS opens a site from the Home Screen.
  def as_home_screen_app
    script = page.driver.browser.execute_cdp(
      "Page.addScriptToEvaluateOnNewDocument",
      source: "Object.defineProperty(navigator, 'standalone', { get: function() { return true; } });"
    )
    yield
  ensure
    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"]) if script
  end

  def navbar_position
    page.evaluate_script("getComputedStyle(document.querySelector('.navbar-fixed-top')).position")
  end

  before { sign_in paid_user }

  it "pins the navbar to the top of a phone web app" do
    on_phone do
      as_home_screen_app do
        visit entries_path

        expect(page).to have_css("html.web-app", visible: :all)
        expect(navbar_position).to eq("fixed")
      end
    end
  end

  it "leaves the navbar scrolling with the page in a phone browser" do
    on_phone do
      visit entries_path

      expect(page).to have_no_css("html.web-app", visible: :all)
      expect(navbar_position).to eq("absolute")
    end
  end

  describe "on marketing pages" do
    def marketing_navbar_background
      page.evaluate_script("getComputedStyle(document.querySelector('[data-navbar]')).backgroundColor")
    end

    it "keeps the navbar solid in a phone web app, even after scrolling" do
      on_phone do
        as_home_screen_app do
          visit mcp_server_docs_path
          expect(page).to have_css("html.web-app", visible: :all)
          expect(marketing_navbar_background).not_to eq("rgba(0, 0, 0, 0)")

          page.execute_script("window.scrollTo(0, 600)")
          expect(page).to have_css("[data-navbar].backdrop-blur-sm")
          expect(marketing_navbar_background).not_to match(/rgba\(.*, 0(\.\d+)?\)|\/ 0?\.\d+\)/)
        end
      end
    end

    it "leaves the navbar see-through at the top of a phone browser" do
      on_phone do
        visit mcp_server_docs_path

        expect(page).to have_no_css("html.web-app", visible: :all)
        expect(marketing_navbar_background).to eq("rgba(0, 0, 0, 0)")
      end
    end
  end
end
