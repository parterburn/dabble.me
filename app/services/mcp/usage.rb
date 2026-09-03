# frozen_string_literal: true

module Mcp
  class Usage
    def initialize(as_of: Time.current)
      @as_of = as_of
    end

    def summary
      {
        connected_now: connected_now,
        connected_ever: connected_ever,
        active_users_7d: active_users_since(as_of - 7.days),
        active_users_30d: active_users_since(as_of - 30.days),
        calls_today: calls_on(as_of.to_date),
        calls_7d: calls_since(as_of - 7.days),
        calls_30d: calls_since(as_of - 30.days),
        oauth_calls_30d: calls_since(as_of - 30.days, source: 'oauth'),
        webmcp_calls_30d: calls_since(as_of - 30.days, source: 'webmcp'),
        success_rate_30d: success_rate_since(as_of - 30.days),
        tools: tool_rows(as_of - 30.days),
        clients: client_rows
      }
    end

    def connected_now
      live_tokens.distinct.count(:resource_owner_id)
    end

    def connected_ever
      Doorkeeper::AccessToken
        .where.not(resource_owner_id: nil)
        .where('scopes LIKE ?', '%mcp:access%')
        .distinct
        .count(:resource_owner_id)
    end

    def active_users_since(start_at)
      invocations.since(start_at).distinct.count(:user_id)
    end

    def calls_since(start_at, source: nil)
      scope = invocations.since(start_at)
      scope = scope.where(source: source) if source
      scope.count
    end

    def calls_on(date)
      invocations.on_day(date).count
    end

    def tool_breakdown_since(start_at)
      invocations.since(start_at).group(:tool_name).count
    end

    def tool_breakdown_on(date)
      invocations.on_day(date).group(:tool_name).count
    end

    def calls_by_day(since: 90.days.ago)
      invocations.where('created_at >= ?', since).group_by_day(:created_at, format: '%b %d').count
    end

    private

    attr_reader :as_of

    def invocations
      McpToolInvocation.where('created_at <= ?', as_of)
    end

    def live_tokens
      scope = Doorkeeper::AccessToken
                .where(revoked_at: nil)
                .where.not(resource_owner_id: nil)
                .where('scopes LIKE ?', '%mcp:access%')
      scope.where(
        'expires_in IS NULL OR created_at + (expires_in * interval \'1 second\') > ?',
        as_of
      )
    end

    def success_rate_since(start_at)
      total = calls_since(start_at)
      return nil if total.zero?

      (invocations.since(start_at).successful.count.to_f / total).round(4)
    end

    def tool_rows(start_at)
      counts = tool_breakdown_since(start_at)
      users = invocations.since(start_at).group(:tool_name).distinct.count(:user_id)
      counts.sort_by { |_name, count| -count }.map do |name, count|
        { name: name, calls: count, users: users[name].to_i }
      end
    end

    def client_rows
      sql = ActiveRecord::Base.sanitize_sql_array([
        <<~SQL.squish,
          SELECT oauth_applications.name AS name,
                 COUNT(DISTINCT oauth_access_tokens.resource_owner_id)::bigint AS users
          FROM oauth_access_tokens
          INNER JOIN oauth_applications
            ON oauth_applications.id = oauth_access_tokens.application_id
          WHERE oauth_access_tokens.revoked_at IS NULL
            AND oauth_access_tokens.resource_owner_id IS NOT NULL
            AND oauth_access_tokens.scopes LIKE '%mcp:access%'
            AND (
              oauth_access_tokens.expires_in IS NULL
              OR oauth_access_tokens.created_at + (oauth_access_tokens.expires_in * interval '1 second') > ?
            )
          GROUP BY oauth_applications.name
          ORDER BY users DESC
        SQL
        as_of
      ])
      ActiveRecord::Base.connection.select_all(sql).map do |row|
        { name: row['name'], users: row['users'].to_i }
      end
    end
  end
end
