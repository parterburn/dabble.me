# frozen_string_literal: true

# Wraps Rack apps mounted for admins (Sidekiq::Web), which skip the
# controller filter in ApplicationController#require_admin_passkey.
# The route around the mount already requires a signed-in admin.
class AdminPasskeyGate
  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    user = env["warden"]&.user(:user)
    return not_found unless AdminAccess.passkey_required?(user)
    return @app.call(env) if AdminAccess.passkey_fresh?(request.session, user)

    AdminAccess.remember_return_to!(request.session, request.original_fullpath) if request.get?
    location = user.webauthn_credentials.exists? ? "/passkeys/verification/new" : "/security"
    [302, { "location" => location, "content-type" => "text/html", "cache-control" => "no-store" }, []]
  end

  private

  def not_found
    [404, { "content-type" => "text/plain" }, ["Not Found"]]
  end
end
