# frozen_string_literal: true

module Oauth
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    # Doorkeeper defaults to layouts/doorkeeper/application (gem), which only loads
    # doorkeeper/application.css — not our app bundle or oauth_consent_bundle.
    layout "application"

    prepend_before_action :mark_oauth_consent_page
    # Prepended so a malformed request is refused before the sign-in redirect, not after it.
    prepend_before_action :enforce_mcp_oauth_rules, only: %i[new create destroy]

    private

    # What the MCP authorization spec asks of the server beyond Doorkeeper's own checks
    # (see Mcp::OauthRules). An unknown client or a missing redirect_uri falls through to
    # Doorkeeper, which already reports those.
    def enforce_mcp_oauth_rules
      client = Doorkeeper::Application.by_uid(params[:client_id].to_s)
      return if client.nil? || params[:redirect_uri].blank?

      # Never redirect to a URI that failed the check (RFC 6749 §3.1.2.4): render the error.
      unless Mcp::OauthRules.exact_redirect_uri?(params[:redirect_uri], client.redirect_uri)
        return render_oauth_rule_error(Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_redirect_uri))
      end

      unless Mcp::OauthRules.allowed_resource?(params[:resource], request.base_url)
        return render_oauth_rule_error(oauth_rule_error(:invalid_target))
      end

      # Doorkeeper's force_pkce exempts confidential clients; OAuth 2.1 and MCP don't.
      return if action_name == 'destroy' || params[:code_challenge].present?

      render_oauth_rule_error(
        Doorkeeper::OAuth::InvalidRequestResponse.new(
          reason: :invalid_code_challenge,
          state: params[:state],
          redirect_uri: params[:redirect_uri]
        )
      )
    end

    def oauth_rule_error(name)
      Doorkeeper::OAuth::ErrorResponse.new(name: name, state: params[:state], redirect_uri: params[:redirect_uri])
    end

    def render_oauth_rule_error(error_response)
      if error_response.redirectable?
        redirect_to error_response.redirect_uri, allow_other_host: true
      else
        render :error, locals: { error_response: error_response }, status: error_response.status
      end
    end

    def mark_oauth_consent_page
      @body_class = "oauth-consent-page"
    end

    def after_successful_authorization(context)
      super
      notify_new_connection
    end

    # Runs after the auth code is issued but before it's exchanged, so any unrevoked
    # token for this app means it was already in Connected apps.
    def notify_new_connection
      application = pre_auth.client.application
      return if MobileApp.client?(application)
      return if Doorkeeper::AccessToken.where(
        resource_owner_id: current_resource_owner.id,
        application_id: application.id,
        revoked_at: nil
      ).exists?

      UserMailer.oauth_app_connected(
        current_resource_owner,
        application.name,
        redirect_host: helpers.oauth_redirect_host(pre_auth.redirect_uri),
        verified: helpers.oauth_application_logo(pre_auth.client, redirect_uri: pre_auth.redirect_uri).present?
      ).deliver_later
    end
  end
end
