# Data-only: registers the first-party iOS app as a public (PKCE) Doorkeeper client.
class CreateMobileAppOauthApplication < ActiveRecord::Migration[6.1]
  def up
    MobileApp.ensure_application!
  end

  def down
    app = MobileApp.application
    return unless app

    Doorkeeper::AccessToken.where(application_id: app.id).delete_all
    Doorkeeper::AccessGrant.where(application_id: app.id).delete_all
    app.delete
  end
end
