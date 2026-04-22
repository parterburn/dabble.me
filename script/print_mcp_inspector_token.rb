# frozen_string_literal: true

# Used by script/mcp_inspector_smoke.sh — prints a single-use Doorkeeper token (stdout only).
abort("Use RAILS_ENV=test") unless Rails.env.test?

require "factory_bot_rails"
include FactoryBot::Syntax::Methods

Doorkeeper::Application.find_or_create_by!(uid: "inspector-smoke-client") do |a|
  a.name = "MCP Inspector Smoke"
  a.redirect_uri = "http://127.0.0.1/cb"
  a.scopes = "mcp:access"
  a.confidential = false
end

app = Doorkeeper::Application.find_by!(uid: "inspector-smoke-client")
user = create(:user, plan: "PRO Monthly PayHere", payhere_id: "999", gumroad_id: "999999999999")
user.generate_otp_secret
user.update!(otp_enabled: true, otp_enabled_on: Time.current)
create(:entry, user: user, date: Date.new(2026, 4, 20), body: "inspector smoke keyword")

tok = Doorkeeper::AccessToken.create!(
  resource_owner_id: user.id,
  application_id: app.id,
  scopes: "mcp:access",
  expires_in: 2.hours
)

$stdout.print(tok.plaintext_token)
$stdout.flush
