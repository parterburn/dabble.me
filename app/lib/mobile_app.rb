# frozen_string_literal: true

# First-party Dabble Me iOS app. From build 109 it signs in natively: email, password and, with
# 2FA on, the code (POST /api/v1/session), or a dabble.me passkey (/api/v1/session/passkey);
# new accounts POST /api/v1/registration. It then calls /api/v1 with a token scoped to SCOPE,
# renewed at /oauth/token with its refresh token. Builds before 109 signed in on the web through
# /oauth/authorize; that path is gone (Oauth::AuthorizationsController refuses this client).
#
# Unlike MCP clients it is open to free and PRO users alike, and its tokens are kept when a user loses PRO —
# that only gates MCP. Password / email / 2FA changes
# still sign the app out (see User#revoke_doorkeeper_oauth_if_credentials_changed).
module MobileApp
  CLIENT_ID = 'dabble-me-ios'
  NAME = 'Dabble Me for iOS'
  SCOPE = 'app:journal'
  # The client record's redirect URI from the old web sign-in. Nothing is sent to it any more;
  # Doorkeeper requires the record to have one.
  REDIRECT_SCHEME = 'me.dabble.app'
  REDIRECT_URI = "#{REDIRECT_SCHEME}:/oauth/callback"
  # The app's ID for universal links: Apple team ID, then the bundle ID.
  APP_ID = 'B79A4CAS56.me.dabble.ios'
  # dabble.me pages the app opens itself when their link is tapped on a phone that has it
  # (the Journal, Today, a new entry, a day's entry, Search, Rewind, which is in the app's Stats). Apple's
  # pattern syntax: ? is one character, * any number. Everything else stays on the web.
  LINK_PATHS = %w[/entries /entries/ /today /write /entries/new /entries/19??/*/* /entries/20??/*/*
                  /search /search/ /rewind /rewind/ /rewind/*].freeze

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

  # A token for the app, as /oauth/token would answer a code exchange: what native sign-in
  # and sign-up (Api::V1::SessionsController, RegistrationsController) hand back. Its refresh
  # token renews at /oauth/token like any other. Sign in with Apple would issue one the same way.
  def issue_token!(user)
    Doorkeeper::AccessToken.create_for(
      application: application || ensure_application!,
      resource_owner: user,
      scopes: SCOPE,
      expires_in: Doorkeeper.config.access_token_expires_in,
      use_refresh_token: true
    )
  end

  def token_response(token)
    {
      access_token: token.plaintext_token,
      token_type: 'Bearer',
      expires_in: token.expires_in,
      refresh_token: token.plaintext_refresh_token,
      scope: token.scopes.to_s,
      created_at: token.created_at.to_i
    }
  end

  # With a password sign-in or sign-up, for an account with no passkey yet: a token that lets
  # the app add one in the next few minutes without asking for the password again
  # (Api::V1::PasskeysController). Passkey sign-in has no need of it. It works only with the
  # access token it came with.
  def passkey_setup(user, token)
    # Admins add passkeys on the web only (Api::V1::PasskeysController#refuse_admin_passkey).
    return {} if user.webauthn_credentials.exists? || AdminAccounts.protected?(user)

    { passkey_setup_token: Api::V1::PasskeysController.setup_token_for(user, token) }
  end

  def client?(application)
    application.present? && application.uid == CLIENT_ID
  end

  def redirect_uri?(uri)
    uri.to_s == REDIRECT_URI
  end
end
