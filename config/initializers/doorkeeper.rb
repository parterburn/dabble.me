# frozen_string_literal: true

Doorkeeper.configure do
  orm :active_record

  # Share Devise session / Warden with the rest of the app (OAuth authorize screens).
  base_controller 'ApplicationController'

  resource_owner_authenticator do
    current_user || warden.authenticate!(scope: :user)
  end

  admin_authenticator do
    if user_signed_in? && current_user.admin?
      # allow Doorkeeper admin UI
    else
      redirect_to(new_user_session_url)
    end
  end

  authorization_code_expires_in 10.minutes
  # MCP / OAuth access tokens (refresh_token remains available for renewal).
  access_token_expires_in 3.months

  force_pkce
  pkce_code_challenge_methods ['S256']

  hash_token_secrets
  hash_application_secrets

  use_refresh_token

  enable_application_owner confirmation: false

  default_scopes 'mcp:access'
  enforce_configured_scopes

  force_ssl_in_redirect_uri do |uri|
    loopback_hosts = %w[localhost 127.0.0.1 ::1]
    !loopback_hosts.include?(uri.host)
  end

  grant_flows %w[authorization_code]

  realm 'OAuth'
end
