# frozen_string_literal: true

# When a user last used each of their connected apps (OAuth clients such as Claude and ChatGPT),
# for the Connected apps list and the unused-apps email (StaleConnectedAppsWorker).
#
# Nothing stamps every request, but two records come close, and last used is the later of them:
# - Access tokens last a day (config/initializers/doorkeeper.rb), so an app that keeps calling
#   Dabble Me trades its refresh token for a new access token at least daily. Its newest token
#   is no more than a day older than its last request. Token rows are never deleted (only
#   revoked) while the user and app exist, so this reaches back to the first connection.
# - MCP tool calls (McpToolInvocation, kept since Sep 2026) carry the exact time of each call.
#
# The iOS app is left out of the stale check: it is listed under Sessions, which shows its own
# last-active time.
class ConnectedAppUsage
  STALE_AFTER = 1.year

  # { application id => last used time } for one user. Nil for an app they never got a token for.
  def self.last_used(user_id, application_ids)
    ids = Array(application_ids)
    return {} if ids.empty?

    tokens = Doorkeeper::AccessToken.where(resource_owner_id: user_id, application_id: ids)
                                    .group(:application_id).maximum(:created_at)
    calls = McpToolInvocation.where(user_id: user_id, oauth_application_id: ids)
                             .group(:oauth_application_id).maximum(:created_at)
    ids.index_with { |id| [tokens[id], calls[id]].compact.max }
  end

  def self.stale?(last_used_at, now: Time.current)
    last_used_at.present? && last_used_at < now - STALE_AFTER
  end

  # { user id => [application id, ...] }: apps each user is still connected to (holds an
  # unrevoked token for, as Connected apps lists them) but hasn't used in STALE_AFTER.
  def self.stale_by_user(now: Time.current)
    cutoff = now - STALE_AFTER
    candidates = Doorkeeper::AccessToken
                 .where.not(resource_owner_id: nil)
                 .where.not(application_id: MobileApp.application_id)
                 .group(:resource_owner_id, :application_id)
                 .having('BOOL_OR(oauth_access_tokens.revoked_at IS NULL)')
                 .having('MAX(oauth_access_tokens.created_at) < ?', cutoff)
                 .pluck(:resource_owner_id, :application_id)
    return {} if candidates.empty?

    called = McpToolInvocation.where(created_at: cutoff.., oauth_application_id: candidates.map(&:last).uniq)
                              .distinct.pluck(:user_id, :oauth_application_id).to_set
    (candidates.to_set - called).group_by(&:first).transform_values { |pairs| pairs.map(&:last).sort }
  end
end
