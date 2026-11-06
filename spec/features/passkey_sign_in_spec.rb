# frozen_string_literal: true

require "rails_helper"

# Drives the passkey JavaScript in Chrome with a virtual authenticator, which
# answers WebAuthn prompts the way a phone or laptop would after Face ID/PIN.
# It also answers a waiting autofill request at once, standing in for the user
# picking the passkey from the email field's suggestions.
RSpec.describe "Passkey sign-in in the browser", type: :feature, js: true do
  # WebAuthn refuses IP-address RP IDs, so these specs run on localhost.
  around do |example|
    original_host = Capybara.app_host
    original_rp_id = WebAuthn.configuration.rp_id
    original_origins = WebAuthn.configuration.allowed_origins

    Capybara.app_host = "http://localhost:#{Capybara.server_port}"
    WebAuthn.configuration.rp_id = "localhost"
    WebAuthn.configuration.allowed_origins = [Capybara.app_host]
    example.run
  ensure
    Capybara.app_host = original_host
    WebAuthn.configuration.rp_id = original_rp_id
    WebAuthn.configuration.allowed_origins = original_origins
  end

  let(:user) { create(:user) }

  # Records which kind of passkey request each page made.
  RECORD_MEDIATION = <<~JS
    (function() {
      if (!navigator.credentials) { return; }
      var get = navigator.credentials.get.bind(navigator.credentials);
      navigator.credentials.get = function(options) {
        localStorage.setItem("passkeyMediation", (options && options.mediation) || "dialog");
        return get(options);
      };
    })();
  JS

  DISABLE_AUTOFILL = 'if (window.PublicKeyCredential) { PublicKeyCredential.isConditionalMediationAvailable = undefined; }'

  def browser
    page.driver.browser
  end

  def run_on_every_page(js)
    result = browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: js)
    @page_scripts << result["identifier"]
  end

  def add_passkey_on_security_page
    sign_in user
    visit security_path
    fill_in "user_current_password", with: user.password
    accept_prompt(with: "Test laptop") { click_button "Add Passkey" }
    expect(page).to have_content("Test laptop")
    expect(user.webauthn_credentials.count).to eq(1)
  end

  def passkey_used?
    user.webauthn_credentials.first.reload.sign_count.positive?
  end

  def mediation_used
    page.evaluate_script('localStorage.getItem("passkeyMediation")')
  end

  # Waits for the passkey script to leave +from+ before checking the session.
  def expect_signed_in(from: new_user_session_path)
    expect(page).to have_no_current_path(from, ignore_query: true, wait: 10)
    visit security_path
    expect(page).to have_current_path(security_path)
  end

  before do
    @page_scripts = []
    @authenticator = browser.add_virtual_authenticator(
      Selenium::WebDriver::VirtualAuthenticatorOptions.new(
        protocol: :ctap2, transport: :internal,
        resident_key: true, user_verification: true, user_verified: true, user_consenting: true
      )
    )
    run_on_every_page(RECORD_MEDIATION)
  end

  # The browser outlives each example: Chrome allows one internal authenticator
  # per session, and page scripts would leak into later specs.
  after do
    @page_scripts.each { |id| browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: id) }
    @authenticator&.remove!
  end

  it "signs in from email-field autofill" do
    add_passkey_on_security_page
    Capybara.reset_sessions!

    visit new_user_session_path

    expect_signed_in
    expect(passkey_used?).to be(true)
    expect(mediation_used).to eq("conditional")
  end

  context "without autofill" do
    before { run_on_every_page(DISABLE_AUTOFILL) }

    it "signs in with the button and no email" do
      add_passkey_on_security_page
      Capybara.reset_sessions!
      visit security_path
      expect(page).to have_current_path(new_user_session_path)

      click_button "Log in with Passkey"

      expect_signed_in
      expect(passkey_used?).to be(true)
      expect(mediation_used).to eq("dialog")
    end

    it "offers the passkey on the two-factor code screen" do
      add_passkey_on_security_page
      user.generate_otp_secret
      user.update!(otp_enabled: true, otp_enabled_on: Time.current)
      Capybara.reset_sessions!

      visit new_user_session_path
      fill_in "user_email", with: user.email
      fill_in "user_password", with: user.password
      click_button "Log in", exact: true
      expect(page).to have_button("Use a passkey instead")
      otp_page = page.current_path

      click_button "Use a passkey instead"

      expect_signed_in(from: otp_page)
      expect(passkey_used?).to be(true)
    end
  end
end
