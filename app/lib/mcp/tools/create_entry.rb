# frozen_string_literal: true

module Mcp
  module Tools
    class CreateEntry < MCP::Tool
      tool_name 'create_entry'
      title 'Create entry'
      description 'Create a journal entry on a given calendar day (defaults to today in the user account timezone). Plain text is turned into HTML paragraphs. If an entry already exists for that day, appends after a separator (same as the web app) unless merge_with_existing is false.'
      annotations(
        read_only_hint: false,
        destructive_hint: false,
        idempotent_hint: false,
        open_world_hint: false
      )
      input_schema(
        type: 'object',
        properties: {
          date: { type: 'string', description: 'Optional YYYY-MM-DD; omitted means today in the account timezone.' },
          body: { type: 'string', description: 'Entry text (plain text; line breaks become paragraphs). HTML is escaped.' },
          merge_with_existing: {
            type: 'boolean',
            description: 'When true (default), append to the existing entry for this date if one exists. When false, return an error if the date is already taken.'
          }
        },
        required: ['body'],
        additionalProperties: false
      )

      def self.call(body:, server_context:, date: nil, merge_with_existing: true)
        user = Helpers.scoped_user!(server_context)
        denied = Helpers.journal_access_response(user)
        return denied if denied

        merge = merge_with_existing != false
        date_str = date.to_s.strip.presence || Helpers.default_entry_date_iso8601(user)

        data = Mcp::EntryCreator.new(user: user).create(
          date_string: date_str,
          body_text: body,
          merge_with_existing: merge
        )

        MCP::Tool::Response.new(
          [{ type: 'text', text: JSON.pretty_generate(data) }],
          structured_content: data
        )
      end
    end
  end
end
