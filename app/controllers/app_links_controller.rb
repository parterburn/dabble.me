# frozen_string_literal: true

# GET /.well-known/apple-app-site-association: tells iOS which dabble.me links the app opens
# (universal links). Apple fetches it without cookies, through its own CDN, when the app is
# installed or updated. `webcredentials` lets the app use dabble.me's passkeys (and offer its
# saved passwords) in its own sign-in form.
class AppLinksController < ApplicationController
  skip_forgery_protection

  def apple_app_site_association
    expires_in 1.hour, public: true
    render json: {
      applinks: {
        details: [
          { appIDs: [MobileApp::APP_ID], components: MobileApp::LINK_PATHS.map { |path| { '/' => path } } }
        ]
      },
      webcredentials: { apps: [MobileApp::APP_ID] }
    }
  end
end
