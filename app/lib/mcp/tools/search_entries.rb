# frozen_string_literal: true

module Mcp
  module Tools
    class SearchEntries < MCP::Tool
      tool_name 'search_entries'
      title 'Search journal entries'
      description 'Find text in the signed-in user’s private Dabble Me journal. Use for requests such as “find every time I mentioned burnout,” searching a quoted phrase, or finding a topic within an inclusive date range. Returns matching entry dates, excerpts, hashtags, and image presence; never searches another user’s journal.'
      annotations(
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: false
      )
      input_schema(
        type: 'object',
        properties: {
          query: {
            type: 'string',
            minLength: 1,
            description: 'Required keyword, topic, or quoted phrase to find in entry text. Examples: burnout, "new job", gratitude.'
          },
          start_date: { type: 'string', description: 'Optional YYYY-MM-DD inclusive start date.' },
          end_date: { type: 'string', description: 'Optional YYYY-MM-DD inclusive end date.' },
          limit: {
            type: 'integer',
            minimum: 1,
            maximum: Mcp::EntrySearch::MAX_LIMIT,
            description: "Maximum matching entries to return (1–#{Mcp::EntrySearch::MAX_LIMIT}; default 50). total_matches still reports the full count."
          }
        },
        required: ['query'],
        additionalProperties: false
      )

      def self.call(query:, server_context:, start_date: nil, end_date: nil, limit: nil)
        user = Helpers.scoped_user!(server_context)
        denied = Helpers.journal_access_response(user)
        return denied if denied

        result = Mcp::EntrySearch.new(user: user).search(
          query: query,
          limit: limit || 50,
          since: start_date,
          until_date: end_date
        )

        data = {
          query: query,
          total_matches: result[:total_matches],
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
