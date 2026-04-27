# frozen_string_literal: true

module Mcp
  module Tools
    class CreateEntry < MCP::Tool
      tool_name 'create_entry'
      title 'Create entry'
      description 'Create a journal entry on a given calendar day (defaults to today in the user account timezone). Plain text is turned into HTML paragraphs. If an entry already exists for that day, appends after a separator (same as the web app) unless merge_with_existing is false. Optionally attach one image via image_url (https, fetched server-side) or image_base64 (raw base64 or data URL); do not send both. For image_base64, resize the image to fit within 800x800 before base64 encoding.'
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
          body: {
            type: 'string',
            description: 'Entry text (plain text; line breaks become paragraphs). HTML is escaped. Use an empty string for an image-only entry when image_url or image_base64 is set.'
          },
          merge_with_existing: {
            type: 'boolean',
            description: 'When true (default), append to the existing entry for this date if one exists. When false, return an error if the date is already taken.'
          },
          image_url: {
            type: 'string',
            description: 'Optional https URL of an image to attach (one image per call). Fetched by the server; private/loopback hosts are rejected. In production, only https URLs are accepted.'
          },
          image_base64: {
            type: 'string',
            description: 'Optional image as base64: either a data URL (data:image/png;base64,...) or raw base64 bytes. Resize the image to fit within 800x800 before encoding. If raw, set image_mime_type (e.g. image/png) or it defaults to image/jpeg.'
          },
          image_mime_type: {
            type: 'string',
            description: 'When image_base64 is raw (not a data URL), MIME type of the decoded bytes, e.g. image/png or image/jpeg.'
          }
        },
        required: ['body'],
        additionalProperties: false
      )

      def self.call(server_context:, body: nil, date: nil, merge_with_existing: true, image_url: nil, image_base64: nil, image_mime_type: nil)
        user = Helpers.scoped_user!(server_context)
        denied = Helpers.journal_access_response(user)
        return denied if denied

        merge = merge_with_existing != false
        date_str = date.to_s.strip.presence || Helpers.default_entry_date_iso8601(user)

        data = Mcp::EntryCreator.new(user: user).create(
          date_string: date_str,
          body_text: body,
          merge_with_existing: merge,
          image_url: image_url,
          image_base64: image_base64,
          image_mime_type: image_mime_type
        )

        MCP::Tool::Response.new(
          [{ type: 'text', text: JSON.pretty_generate(data) }],
          structured_content: data
        )
      end
    end
  end
end
