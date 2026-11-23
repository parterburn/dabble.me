# frozen_string_literal: true

# Connected apps (Claude, ChatGPT, other OAuth clients) lose access after IDLE_AFTER without
# use; the iOS app after APP_IDLE_AFTER. The clock restarts on every use, so an app in use
# never expires.
#
# That works without a last-used column: access tokens last a day
# (config/initializers/doorkeeper.rb) and refresh tokens rotate, so an app that calls Dabble
# Me at all trades its refresh token for a new token row at least daily. A token row's
# created_at is when its app last refreshed, and a live refresh token older than the limit
# belongs to an app idle that long.
#
# Enforced twice: /oauth/token refuses (and revokes) an idle refresh token
# (Oauth::TokensController), and OauthIdleTokenWorker revokes the rest nightly so Connected
# apps and the Sessions list stop showing them. Rows are revoked, never deleted, which
# ConnectedAppUsage relies on. No email is sent.
#
# Tokens with no expiry (expires_in NULL) never need a refresh, so their age says nothing
# about use; they're left alone.
module OauthIdleExpiry
  IDLE_AFTER = 30.days
  APP_IDLE_AFTER = 1.year

  module_function

  def idle_after(application_id)
    mobile_id = MobileApp.application_id
    mobile_id && application_id == mobile_id ? APP_IDLE_AFTER : IDLE_AFTER
  end

  def idle?(token, now: Time.current)
    return false if token.expires_in.nil?

    token.created_at < now - idle_after(token.application_id)
  end

  # Unrevoked tokens past their app's idle limit.
  def idle_tokens(now: Time.current)
    live = Doorkeeper::AccessToken.where(revoked_at: nil).where.not(expires_in: nil)
    mobile_id = MobileApp.application_id
    return live.where(created_at: ...(now - IDLE_AFTER)) unless mobile_id

    live.where.not(application_id: mobile_id).where(created_at: ...(now - IDLE_AFTER))
        .or(live.where(application_id: mobile_id).where(created_at: ...(now - APP_IDLE_AFTER)))
  end
end
