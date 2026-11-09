# frozen_string_literal: true

require "rails_helper"

# Bootstrap's JavaScript was replaced by app/assets/javascripts/ui.js and
# Summernote's lite build. These cover the pieces people click on.
RSpec.describe "Navbar menus, tooltips and the entry editor", type: :feature, js: true do
  include_context "has all objects"

  before { sign_in paid_user }

  def on_phone
    page.current_window.resize_to(390, 844)
    yield
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  # A click on the page that isn't on the menu (the test can't click "nothing").
  def click_outside
    page.execute_script("document.getElementById('main-container').dispatchEvent(new MouseEvent('click', { bubbles: true }))")
  end

  it "opens the account menu on click and closes it on an outside click" do
    visit entries_path

    find(".s-avatar-toggle").click
    expect(page).to have_css("li.dropdown.open > .s-avatar-toggle[aria-expanded='true']")

    click_outside
    expect(page).to have_no_css("li.dropdown.open")
    expect(page).to have_css(".s-avatar-toggle[aria-expanded='false']")
  end

  it "closes the account menu on Escape" do
    visit entries_path

    find(".s-avatar-toggle").click
    expect(page).to have_css("li.dropdown.open")

    find(".s-avatar-toggle").send_keys(:escape)
    expect(page).to have_no_css("li.dropdown.open")
  end

  it "opens the phone menu from the hamburger button" do
    on_phone do
      visit entries_path
      expect(page).to have_no_link("Account Security")

      find(".navbar-toggle").click

      expect(page).to have_css(".navbar-collapse.in")
      expect(page).to have_link("Account Security")
    end
  end

  it "shows an element's title as a tooltip on hover" do
    visit entries_path
    tip_target = first("[rel='tooltip']")
    title = tip_target["data-original-title"]
    expect(title).to be_present

    tip_target.hover

    expect(page).to have_css(".tooltip.in .tooltip-inner", text: title)
    # Screen readers announce it through aria-describedby while it shows.
    tooltip_id = find(".tooltip.in")["id"]
    expect(tooltip_id).to be_present
    expect(tip_target["aria-describedby"]).to eq(tooltip_id)

    find(".navbar-brand").hover
    expect(page).to have_no_css(".tooltip")
    expect(tip_target["aria-describedby"]).to be_nil
  end

  it "inserts a link from the editor's link dialog" do
    visit new_entry_path
    # Type and select with the keyboard: Summernote only records a selection
    # from key and mouse events, not one set from script.
    editor = find(".note-editable")
    editor.click
    editor.send_keys("see example", [:shift, :home])

    find(".note-toolbar button[aria-label^='Link']").click
    within(".note-modal.link-dialog") do
      expect(find(".note-link-text").value).to eq("see example")
      find(".note-link-url").set("example.com")
      find(".note-link-btn").click
    end

    expect(page).to have_css(".note-editable a[href='http://example.com']", text: "see example")
    expect(page).to have_no_css(".note-modal.link-dialog.open")
  end
end
