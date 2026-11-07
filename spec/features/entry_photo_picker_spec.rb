# frozen_string_literal: true

require "rails_helper"
require "base64"

# Drives the photo field on the new and edit entry forms in Chrome.
RSpec.describe "Entry photo picker", type: :feature, js: true do
  include_context "has all objects"

  PNG_1PX = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")

  around do |example|
    Dir.mktmpdir do |dir|
      @photo_dir = dir
      example.run
    end
  end

  def photo_files(count, prefix: "photo")
    Array.new(count) do |i|
      path = File.join(@photo_dir, "#{prefix}-#{i + 1}.png")
      File.binwrite(path, PNG_1PX)
      path
    end
  end

  def thumbnails
    all(".photo-picker__thumb")
  end

  def selected_file_names
    page.evaluate_script("Array.prototype.map.call(document.getElementById('entry_image').files, function(f) { return f.name; })")
  end

  # The test browser has a mouse (spec/support/config/capybara.rb). Touch
  # emulation makes it match (hover: none) like a phone until turned off.
  def with_touch_screen
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 5)
    yield
  ensure
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: false)
  end

  def write_body(text)
    page.execute_script("$('#entry_entry').summernote('code', #{text.to_json})")
  end

  before { sign_in paid_user }

  describe "new entry" do
    it "shows a drop zone instead of labels" do
      visit new_entry_path

      expect(page).to have_css(".photo-picker__drop", text: "Add photo(s)")
      # Date and Entry keep labels for screen readers only; the photo field has none.
      expect(page).to have_css("label.sr-only[for='entry_date']", visible: :all)
      expect(page).to have_css("label.sr-only[for='entry_entry']", visible: :all)
      expect(page).to have_no_css("label:not(.sr-only)", text: /\A(Date|Entry|Photo)\z/, visible: :all)
    end

    it "says to drag or click with a mouse" do
      visit new_entry_path

      expect(page).to have_css(".photo-picker__hint", text: "Drag photos here or click to browse")
      expect(page).to have_no_content("photos per entry")
    end

    it "shows only the title on a touch screen" do
      with_touch_screen do
        visit new_entry_path

        expect(page).to have_css(".photo-picker__drop", text: "Add photo(s)")
        expect(page).to have_no_css(".photo-picker__hint", visible: true)
      end
    end

    it "previews chosen photos, removes one, and uploads the rest" do
      received = []
      allow_any_instance_of(EntriesController).to receive(:collage_from_attachments) do |_controller, attachments|
        received.concat(attachments.map(&:original_filename))
        []
      end
      allow(ImageCollageJob).to receive(:perform_later)

      visit new_entry_path
      attach_file "entry_image", photo_files(3), make_visible: true

      expect(page).to have_css(".photo-picker__thumb", count: 3)
      expect(page).to have_css(".photo-picker__drop.is-compact", text: "Add more photos")
      expect(page).to have_css(".photo-picker__count", text: "3 of #{CollageGenerator::MAX_IMAGES} photos")

      thumbnails[1].find(".photo-picker__remove").click

      expect(page).to have_css(".photo-picker__thumb", count: 2)
      expect(page).to have_css(".photo-picker__count", text: "2 of #{CollageGenerator::MAX_IMAGES} photos")
      expect(selected_file_names).to eq(["photo-1.png", "photo-3.png"])

      write_body("<p>Pictures from the weekend.</p>")
      click_button "Create Entry"

      expect(page).to have_content("Merged with existing entry").or have_content("Entry created successfully")
      expect(received).to eq(["photo-1.png", "photo-3.png"])
    end

    it "keeps photos up to the limit and explains what it skipped" do
      max = CollageGenerator::MAX_IMAGES
      visit new_entry_path

      attach_file "entry_image", photo_files(max + 1), make_visible: true

      expect(page).to have_css(".photo-picker__thumb", count: max)
      expect(page).to have_css(".photo-picker__message", text: "You can add up to #{max} photos, so 1 photo didn't fit.")
      expect(page).to have_no_css(".photo-picker__drop", visible: true)
      expect(selected_file_names.size).to eq(max)

      thumbnails.first.find(".photo-picker__remove").click
      expect(page).to have_css(".photo-picker__drop", text: "Add more photos")
    end

    it "adds to the photos already chosen instead of replacing them" do
      visit new_entry_path

      attach_file "entry_image", photo_files(2, prefix: "first"), make_visible: true
      expect(page).to have_css(".photo-picker__thumb", count: 2)
      attach_file "entry_image", photo_files(1, prefix: "second"), make_visible: true

      expect(page).to have_css(".photo-picker__thumb", count: 3)
      expect(selected_file_names).to eq(["first-1.png", "first-2.png", "second-1.png"])
    end
  end

  describe "editing an entry with a photo" do
    before do
      paid_entry.update_columns(image: "lake.jpg", body: "<p>By the lake.</p>")

      # Keep CarrierWave from calling S3 while the entry is validated and saved.
      allow_any_instance_of(ImageUploader).to receive(:remove!).and_return(true)
      allow_any_instance_of(ImageUploader).to receive(:relocate_between_dates!).and_return(nil)
      allow_any_instance_of(ImageUploader).to receive(:blank?).and_return(false)
      fog_file = instance_double(
        CarrierWave::Storage::Fog::File,
        content_type: "image/jpeg",
        filename: "lake.jpg",
        path: "uploads/test/key/lake.jpg",
        empty?: false,
        exists?: true,
        delete: true,
        size: 10
      )
      allow_any_instance_of(ImageUploader).to receive(:file).and_return(fog_file)
    end

    it "removes the photo from the page with the ×, and from the entry on save" do
      visit edit_entry_path(paid_entry)

      expect(page).to have_css(".photo-picker__current img")
      expect(page).to have_no_css(".photo-picker__drop", visible: true)
      expect(page).to have_no_content("Remove Photo")

      find(".j-photo-remove-current").click

      expect(page).to have_no_css(".photo-picker__current", visible: true)
      expect(page).to have_content("Photo will be removed when you save.")
      expect(page).to have_css(".photo-picker__drop", text: "Add photo(s)")
      expect(find("#entry_remove_image", visible: :all).value).to eq("1")

      click_button "Update Entry"

      expect(page).to have_content("Entry successfully updated!")
      expect(paid_entry.reload[:image]).to be_nil
    end

    it "keeps the photo when the removal is undone" do
      visit edit_entry_path(paid_entry)

      find(".j-photo-remove-current").click
      click_button "Undo"

      expect(page).to have_css(".photo-picker__current img")
      expect(page).to have_no_css(".photo-picker__drop", visible: true)
      expect(find("#entry_remove_image", visible: :all).value).to eq("0")
    end
  end
end
