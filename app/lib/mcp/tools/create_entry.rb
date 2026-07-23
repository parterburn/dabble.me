# frozen_string_literal: true

module Mcp
  module Tools
    class CreateEntry < MCP::Tool
      tool_name 'create_entry'
      title 'Create or append a journal entry'
      description 'Write to the signed-in user’s private Dabble Me journal on a calendar day (default: today in the account timezone). Plain text becomes paragraphs. By default, text appends to an existing entry on that day; set merge_with_existing false to fail instead. Optionally attach one image using uploaded_image_key (preferred), a public HTTPS image URL, or small base64 data.'
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
          uploaded_image_key: {
            type: 'string',
            description: 'Preferred image attachment flow. First call get_image_upload_url, upload the image bytes with the returned PUT URL and headers, then pass the returned uploaded_image_key here. Do not combine with image_url or image_base64.'
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

      def self.call(server_context:, body: nil, date: nil, merge_with_existing: true, image_url: nil, image_base64: nil, image_mime_type: nil, uploaded_image_key: nil)
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
          image_mime_type: image_mime_type,
          uploaded_image_key: uploaded_image_key
        )

        MCP::Tool::Response.new(
          [{ type: 'text', text: JSON.pretty_generate(data) }],
          structured_content: data
        )
      end
    end
  end
end
