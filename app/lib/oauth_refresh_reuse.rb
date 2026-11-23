# frozen_string_literal: true

# A refresh token is good for one refresh: Doorkeeper revokes it and hands out a new one
# (refresh token rotation). If the old one shows up again, two parties held it, and the one
# that refreshed first may be someone who stole it.
#
# Clients sometimes send two refreshes at once (MCP clients do), so a reuse within GRACE of the
# rotation is the client's own race and is only refused, as Doorkeeper refuses it anyway. Past
# GRACE, the tokens issued after it for the same app and account (and, for the iOS app, the
# same device) are revoked, and the user is emailed. The app has to connect again; whoever
# holds the copy loses access too.
#
# A token revoked for any other reason (removed in Connected apps, idle expiry, sign out of all
# devices, a password change) leaves no live token after it, so reusing it does nothing here.
module OauthRefreshReuse
  GRACE = 60.seconds
  # The new token is created in the same request that revokes the old one.
  ROTATION_SLACK = 5.seconds

  module_function

  # The old token's successors still alive, or none when this isn't a suspicious reuse.
  def successors(token, now: Time.current)
    return Doorkeeper::AccessToken.none unless token&.revoked_at && token.revoked_at <= now - GRACE

    scope = Doorkeeper::AccessToken.where(
      resource_owner_id: token.resource_owner_id,
      application_id: token.application_id,
      revoked_at: nil
    ).where(created_at: (token.revoked_at - ROTATION_SLACK)..)
    scope = scope.where(user_session_id: token.user_session_id) if token.respond_to?(:user_session_id) && token.user_session_id
    scope
  end

  # Revokes the successors and emails the user. True when it did.
  def handle!(token, now: Time.current)
    live = successors(token, now: now)
    return false unless live.exists?

    live.update_all(revoked_at: now)
    Doorkeeper::AccessGrant.where(
      resource_owner_id: token.resource_owner_id,
      application_id: token.application_id,
      revoked_at: nil
    ).update_all(revoked_at: now)

    user = User.find_by(id: token.resource_owner_id)
    app_name = token.application&.name
    UserMailer.oauth_refresh_token_reused(user, app_name).deliver_later if user && app_name
    Sentry.capture_message('OAuth refresh token reused after rotation', level: :warning,
                                                                         extra: { application_id: token.application_id })
    true
  end
end
