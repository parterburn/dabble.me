# frozen_string_literal: true

require "rails_helper"

# The admin passkey check in Chrome, with a virtual authenticator answering
# the WebAuthn prompts (see passkey_sign_in_spec.rb).
RSpec.describe "Admin passkey check in the browser", type: :feature, js: true do
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

  let(:admin) { create(:user, admin: true) }

  before do
    @authenticator = page.driver.browser.add_virtual_authenticator(
      Selenium::WebDriver::VirtualAuthenticatorOptions.new(
        protocol: :ctap2, transport: :internal,
        resident_key: true, user_verification: true, user_verified: true, user_consenting: true
      )
    )
  end

  after { @authenticator&.remove! }

  it "has an admin add a passkey, then confirm it after a password sign-in" do
    sign_in admin
    visit admin_users_path
    expect(page).to have_current_path(security_path)
    expect(page).to have_content("Admin accounts need a passkey")

    fill_in "user_current_password", with: admin.password
    accept_prompt(with: "Test laptop") { click_button "Add Passkey" }
    expect(page).to have_content("Test laptop")

    Capybara.reset_sessions!
    sign_in admin
    visit admin_users_path
    expect(page).to have_current_path(new_passkeys_verification_path)

    click_button "Use my passkey"

    expect(page).to have_current_path(admin_users_path, wait: 10)
    expect(admin.webauthn_credentials.first.reload.sign_count).to be_positive
  end
end
