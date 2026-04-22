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
  end
end
