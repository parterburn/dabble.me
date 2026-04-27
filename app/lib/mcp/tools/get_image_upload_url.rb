# frozen_string_literal: true

module Mcp
  module Tools
    class GetImageUploadUrl < MCP::Tool
      tool_name 'get_image_upload_url'
      title 'Get image upload URL'
      description 'Return a short-lived presigned S3 PUT URL for uploading one journal image directly outside the MCP tool-call payload. Use this for user-uploaded/local images to avoid sending base64 through MCP. After uploading with the returned method and headers, pass uploaded_image_key to create_entry.'
      annotations(
        read_only_hint: false,
        destructive_hint: false,
        idempotent_hint: false,
        open_world_hint: false
      )
      input_schema(
        type: 'object',
        properties: {
          filename: {
            type: 'string',
            description: 'Original image filename, used only to choose a safe extension. Example: photo.jpg.'
          },
          content_type: {
            type: 'string',
            description: 'Image MIME type for the upload, e.g. image/jpeg, image/png, image/webp, image/heic.'
          }
        },
        required: ['content_type'],
        additionalProperties: false
      )

      def self.call(server_context:, filename: nil, content_type: nil)
        user = Helpers.scoped_user!(server_context)
        denied = Helpers.journal_access_response(user)
        return denied if denied

        data = Mcp::PresignedImageUpload.new(user: user).call(
          filename: filename,
          content_type: content_type
        )

        MCP::Tool::Response.new(
          [{ type: 'text', text: JSON.pretty_generate(data) }],
          structured_content: data
        )
      end
    end
  end
end
