# frozen_string_literal: true

module Mcp
  module Tools
    module Helpers
      module_function

      # Always load the journal owner from MCP server_context — never from tool arguments.
      def scoped_user!(server_context)
        raise ArgumentError, 'Missing MCP server context' unless server_context

        user_id = server_context[:user_id]
        raise ArgumentError, 'Missing user_id in server context' if user_id.blank?

        User.find(user_id)
      end

      def journal_access_response(user)
        return nil if user.is_pro? && user.mcp_security_requirements_met? && !user.deletion_pending?

        MCP::Tool::Response.new(
          [{
            type: 'text',
            text: 'Dabble Me MCP requires PRO, a passkey or two-factor authentication, and an active account.'
          }],
          error: true
        )
      end

      def normalize_entry_row(entry)
        {
          id: entry[:id],
          date: entry[:date],
          excerpt: entry[:text_body].to_s.squish.truncate(400),
          hashtags: entry[:hashtags],
          has_image: entry[:has_image]
        }
      end

      def default_entry_date_iso8601(user)
        tz = ActiveSupport::TimeZone[user.send_timezone] || Time.zone
        Time.current.in_time_zone(tz).to_date.iso8601
      end
    end
  end
end
