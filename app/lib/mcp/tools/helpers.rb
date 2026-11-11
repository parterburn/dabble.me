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

      def with_logged_invocation(tool_name, server_context, source: 'oauth')
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = yield
        Mcp::InvocationLogger.record_from_response(
          tool_name: tool_name,
          server_context: server_context,
          source: source,
          response: response,
          duration_ms: elapsed_ms(started)
        )
        response
      rescue StandardError
        Mcp::InvocationLogger.record(
          user_id: server_context && server_context[:user_id],
          tool_name: tool_name,
          source: source,
          success: false,
          duration_ms: elapsed_ms(started),
          oauth_application_id: server_context && server_context[:oauth_application_id]
        )
        raise
      end

      def elapsed_ms(started)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      end

      def journal_access_response(user)
        return nil if user.is_pro? && !user.deletion_pending?

        MCP::Tool::Response.new(
          [{
            type: 'text',
            text: 'The Dabble Me connector requires a paid [Dabble Me PRO](https://dabble.me/subscribe) account.'
          }],
          error: true
        )
      end

      def normalize_entry_row(entry)
        {
          id: entry[:id],
          date: entry[:date],
          excerpt: append_entry_extras(entry[:text_body].to_s.squish.truncate(5000), entry[:songs_text], entry[:tags_text]),
          hashtags: entry[:hashtags],
          has_image: entry[:has_image],
          image_url: entry[:image_url]
        }
      end

      # Songs and dated tags sit after the entry text so a long excerpt cannot truncate them away.
      def append_entry_extras(text, songs_text, tags_text)
        [text.to_s.presence, songs_text.presence, tags_text.presence].compact.join("\n\n")
      end

      def default_entry_date_iso8601(user)
        tz = ActiveSupport::TimeZone[user.send_timezone] || Time.zone
        Time.current.in_time_zone(tz).to_date.iso8601
      end

      def entry_public_url(entry_or_date)
        date = entry_or_date.respond_to?(:date) ? entry_or_date.date : entry_or_date
        date = date.to_date

        "#{ApplicationHelper.site_public_base_url}/entries/#{date.year}/#{date.month}/#{date.day}"
      end
    end
  end
end
