# frozen_string_literal: true

require "rails_helper"

# iOS 26 and later blur the top of a Home Screen web app unless a solid bar is
# fixed to the top edge, so the navbar stays pinned there on phones.
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
end
