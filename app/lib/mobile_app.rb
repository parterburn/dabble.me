# frozen_string_literal: true

# First-party Dabble Me iOS app. It signs in via OAuth (authorization code + PKCE)
# through the normal web login, so passkeys / 2FA / password all keep working, and
# then calls /api/v1 with a token scoped to SCOPE.
#
# Unlike MCP clients it is open to free and PRO users alike, skips the consent
# screen (it's our own app), and its tokens are kept when a user loses PRO —
# that only gates MCP. Password / email / 2FA changes
# still sign the app out (see User#revoke_doorkeeper_oauth_if_credentials_changed).
module MobileApp
  CLIENT_ID = 'dabble-me-ios'
  NAME = 'Dabble Me for iOS'
  SCOPE = 'app:journal'
  # RFC 8252 private-use URI scheme (reverse DNS of dabble.me). ASWebAuthenticationSession
  # delivers the callback only to the app that started the session.
  REDIRECT_SCHEME = 'me.dabble.app'
  REDIRECT_URI = "#{REDIRECT_SCHEME}:/oauth/callback"

  module_function

  def application
    Doorkeeper::Application.find_by(uid: CLIENT_ID)
  end

  def application_id
    application&.id
  end

  # Idempotent; run by the CreateMobileAppOauthApplication migration and db:seed.
  def ensure_application!
    Doorkeeper::Application.find_or_create_by!(uid: CLIENT_ID) do |app|
      app.name = NAME
      app.redirect_uri = REDIRECT_URI
      app.scopes = SCOPE
      app.confidential = false
    end
  end

  def client?(application)
    application.present? && application.uid == CLIENT_ID
  end

  def redirect_uri?(uri)
    uri.to_s == REDIRECT_URI
  end
end
