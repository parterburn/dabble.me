# frozen_string_literal: true

module Oauth
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    # Doorkeeper defaults to layouts/doorkeeper/application (gem), which only loads
    # doorkeeper/application.css — not our app bundle or oauth_consent_bundle.
    layout "application"

    prepend_before_action :mark_oauth_consent_page

    private

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
