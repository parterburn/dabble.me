# frozen_string_literal: true

# A refresh token is good for one refresh: Doorkeeper revokes it and hands out a new one
# (refresh token rotation). If the old one shows up again, two parties held it, and the one
# that refreshed first may be someone who stole it.
#
# Clients sometimes send two refreshes at once (MCP clients do), so a reuse within GRACE of the
# rotation is the client's own race and is only refused, as Doorkeeper refuses it anyway. Past
# GRACE, every live token descended from the same sign-in is revoked and the user is emailed.
# The app has to connect again; whoever holds the copy loses access too. A client that shares
# one refresh token between processes can trip this too: the Sentry message shows how often.
#
# Lineage: each rotated token carries refresh_chain_id, the id of the token that began its
# chain (record_rotation, from Doorkeeper's after_successful_strategy_response). A token was
# rotated if its chain has a newer token. One revoked any other way (removed in Connected apps,
# idle expiry, sign out of all devices, a password change) was the end of its chain, so replaying
# it does nothing here, and a later sign-in starts a new chain it can't reach.
#
# Tokens rotated before refresh_chain_id existed have no lineage; a replay of one is only refused.
module OauthRefreshReuse
  GRACE = 60.seconds

  module_function

  def record_rotation(old_token, new_token)
    return unless old_token && new_token&.persisted?

    new_token.update_column(:refresh_chain_id, chain_id(old_token))
  end

  def chain_id(token)
    token.refresh_chain_id || token.id
  end

  # Live tokens in the replayed token's chain, or none when this isn't a suspicious reuse.
  def live_descendants(token, now: Time.current)
    none = Doorkeeper::AccessToken.none
    return none unless token&.revoked_at && token.revoked_at <= now - GRACE

    chain = Doorkeeper::AccessToken.where(refresh_chain_id: chain_id(token)).where('id > ?', token.id)
    return none unless chain.exists? # the end of its chain: revoked some other way, not rotated

    chain.where(revoked_at: nil)
  end

  # Revokes the chain's live tokens and emails the user. True when it did.
  #
  # The rows are locked, as Doorkeeper locks a token while it rotates it, so a refresh racing
  # this one either finishes first or finds its token revoked. One gap remains: a token created
  # by a refresh that commits in the same instant gets its refresh_chain_id a moment later
  # (record_rotation runs after Doorkeeper's transaction) and is missed.
  def handle!(token, now: Time.current)
    revoked = Doorkeeper::AccessToken.transaction do
      ids = live_descendants(token, now: now).lock.pluck(:id)
      next false if ids.empty?

      Doorkeeper::AccessToken.where(id: ids).update_all(revoked_at: now)
      true
    end
    return false unless revoked

    user = User.find_by(id: token.resource_owner_id)
    app_name = token.application&.name
    UserMailer.oauth_refresh_token_reused(user, app_name).deliver_later if user && app_name
    Sentry.capture_message('OAuth refresh token reused after rotation', level: :warning,
                                                                         extra: { application_id: token.application_id })
    true
  end
end
