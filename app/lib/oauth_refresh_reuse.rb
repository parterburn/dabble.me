# frozen_string_literal: true

# A refresh token is good for one refresh: Doorkeeper revokes it and hands out a new one
# (refresh token rotation). If the old one shows up again, two parties held it, and the one
# that refreshed first may be someone who stole it.
#
# Clients sometimes send two refreshes at once (MCP clients do), so a reuse within GRACE of the
# rotation is the client's own race and is only refused, as Doorkeeper refuses it anyway. Past
# GRACE, the live token at the end of the old token's rotation chain is revoked, and the user is
# emailed. The app has to connect again; whoever holds the copy loses access too.
#
# There's no lineage column, so the chain is rebuilt from timing: a refresh revokes the old row
# and creates its successor in the same request, so a token's successor is the row for the same
# account, app (and, for the iOS app, device) created within ROTATION_SLACK of its revoked_at. A
# token revoked any other way (removed in Connected apps, idle expiry, sign out of all devices, a
# password change) has no such row, so replaying it can't touch a connection authorized later.
module OauthRefreshReuse
  GRACE = 60.seconds
  ROTATION_SLACK = 2.seconds
  # A year of daily refreshes, with room to spare.
  MAX_CHAIN = 1_000

  module_function

  # The live token the old one was rotated into, or nil when this isn't a suspicious reuse.
  def live_successor(token, now: Time.current)
    return nil unless token&.revoked_at && token.revoked_at <= now - GRACE

    current = token
    MAX_CHAIN.times do
      successor = rotated_into(current)
      return nil unless successor
      return successor if successor.revoked_at.nil?

      current = successor
    end
    nil
  end

  def rotated_into(token)
    scope = Doorkeeper::AccessToken.where(
      resource_owner_id: token.resource_owner_id,
      application_id: token.application_id,
      created_at: (token.revoked_at - ROTATION_SLACK)..(token.revoked_at + ROTATION_SLACK)
    ).where.not(id: token.id).where('id > ?', token.id)
    scope = scope.where(user_session_id: token.user_session_id) if token.user_session_id
    scope.order(:id).first
  end

  # Revokes the successor and emails the user. True when it did.
  def handle!(token, now: Time.current)
    live = live_successor(token, now: now)
    return false unless live

    live.update_columns(revoked_at: now)

    user = User.find_by(id: token.resource_owner_id)
    app_name = token.application&.name
    UserMailer.oauth_refresh_token_reused(user, app_name).deliver_later if user && app_name
    Sentry.capture_message('OAuth refresh token reused after rotation', level: :warning,
                                                                         extra: { application_id: token.application_id })
    true
  end
end
