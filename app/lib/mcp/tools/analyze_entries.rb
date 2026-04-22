# frozen_string_literal: true

module Mcp
  module Tools
    class AnalyzeEntries < MCP::Tool
      tool_name 'analyze_entries'
      title 'Analyze entries'
      description 'Return counts, date coverage, top hashtags, and writing volume summaries over your own entries.'
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
          end_date: { type: 'string', description: 'Optional YYYY-MM-DD inclusive end date.' }
        },
        additionalProperties: false
      )

      def self.call(server_context:, start_date: nil, end_date: nil)
        user = Helpers.scoped_user!(server_context)
        denied = Helpers.journal_access_response(user)
        return denied if denied

        result = Mcp::EntrySearch.new(user: user).analyze(
          query: nil,
          since: start_date,
          until_date: end_date
        )

        data = {
          total_entries: result[:total_matches],
          date_range: result[:date_range],
          entry_count_by_year: result[:entry_count_by_year],
          top_hashtags: result[:most_used_hashtags].map { |tag| { hashtag: tag[:tag], count: tag[:count] } },
          average_words_per_entry: result[:average_entry_length_words],
          sample_entries: result[:sample_highlights]
        }

        MCP::Tool::Response.new(
          [{ type: 'text', text: JSON.pretty_generate(data) }],
          structured_content: data
        )
      end
    end
  end
end
