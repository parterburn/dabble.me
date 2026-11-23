# frozen_string_literal: true

# When a user last used each of their connected apps (OAuth clients such as Claude and ChatGPT),
# for the "Last used" date on the Connected apps list.
#
# Nothing stamps every request, but two records come close, and last used is the later of them:
# - Access tokens last a day (config/initializers/doorkeeper.rb), so an app that keeps calling
#   Dabble Me trades its refresh token for a new access token at least daily. Its newest token
#   is no more than a day older than its last request. Token rows are never deleted (only
#   revoked) while the user and app exist, so this reaches back to the first connection.
# - MCP tool calls (McpToolInvocation, kept since Sep 2026) carry the exact time of each call.
#
# Unused apps are disconnected after a while (OauthIdleExpiry), which revokes their token rows
# but keeps them, so this still works.
class ConnectedAppUsage
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
end
