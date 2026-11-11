# frozen_string_literal: true

Doorkeeper.configure do
  orm :active_record

  # Share Devise session / Warden with the rest of the app (OAuth authorize screens).
  base_controller 'ApplicationController'

  # Doorkeeper's documented pattern: send signed-out users to the login page and back here
  # afterwards, without Devise's "You need to login or sign up" flash (the iOS app and AI
  # connectors open this page right after the person chose to sign in).
  # `prompt=create` (OpenID Connect's standard hint) opens the sign-up page instead, for the
  # iOS app's "Create Account" button; Devise returns new users here after signing up.
  resource_owner_authenticator do
    current_user || begin
      store_location_for(:user, request.fullpath)
      redirect_to(params[:prompt] == 'create' ? new_user_registration_url : new_user_session_url)
      nil
    end
  end

  # /oauth/applications. Doorkeeper's controllers inherit ApplicationController,
  # so the admin passkey check (require_admin_passkey) also applies here.
  admin_authenticator do
    if !CloudflareAccess.allowed?(request)
      head :not_found
    elsif user_signed_in? && current_user.admin?
      # allow Doorkeeper admin UI
    else
      redirect_to(new_user_session_url)
    end
  end

  authorization_code_expires_in 10.minutes
  # MCP / OAuth access tokens. Clients renew with the refresh token, which rotates on use.
  access_token_expires_in 1.day

  force_pkce
  pkce_code_challenge_methods ['S256']

  hash_token_secrets
  hash_application_secrets

  use_refresh_token

  enable_application_owner confirmation: false

  default_scopes 'mcp:access'
  # First-party iOS app only (see MobileApp). Not advertised in OAuth metadata, and
  # dynamic client registration always assigns mcp:access.
  optional_scopes 'app:journal'
  enforce_configured_scopes

  # Our own iOS app doesn't need a consent screen for access to its own account.
  skip_authorization do |_resource_owner, client|
    MobileApp.client?(client.application)
  end

  force_ssl_in_redirect_uri do |uri|
    loopback_hosts = %w[localhost 127.0.0.1 ::1]
    !loopback_hosts.include?(uri.host)
  end

  forbid_redirect_uri do |uri|
    scheme = uri.scheme.to_s.downcase
    loopback_hosts = %w[localhost 127.0.0.1 ::1]
    if scheme == 'https'
      uri.host.blank?
    elsif scheme == 'http'
      !loopback_hosts.include?(uri.host)
    else
      !MobileApp.redirect_uri?(uri)
    end
  end

  grant_flows %w[authorization_code]

  realm 'OAuth'
end
