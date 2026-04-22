# frozen_string_literal: true

module Mcp
  module Tools
    class ListEntries < MCP::Tool
      tool_name 'list_entries'
      title 'List entries'
      description 'List your own entries for a date range, newest first.'
      annotations(
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: false
      )
      input_schema(
        type: 'object',
        properties: {
          start_date: { type: 'string', description: 'Optional YYYY-MM-DD inclusive start date.' },
          end_date: { type: 'string', description: 'Optional YYYY-MM-DD inclusive end date.' },
          limit: { type: 'integer', minimum: 1, maximum: 100 }
        },
        additionalProperties: false
      )

      def self.call(server_context:, start_date: nil, end_date: nil, limit: nil)
        user = Helpers.scoped_user!(server_context)
        denied = Helpers.journal_access_response(user)
        return denied if denied

        result = Mcp::EntrySearch.new(user: user).list(
          limit: limit || 20,
          since: start_date,
          until_date: end_date
        )

        data = {
          total_entries: result[:total_matches],
          entries: result[:entries].map { |e| Helpers.normalize_entry_row(e) }
        }

        MCP::Tool::Response.new(
          [{ type: 'text', text: JSON.pretty_generate(data) }],
          structured_content: data
        )
      end
    end
  end
end
