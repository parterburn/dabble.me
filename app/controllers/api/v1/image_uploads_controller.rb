# frozen_string_literal: true

module Api
  module V1
    # Presigned S3 PUT for one photo; pass the returned uploaded_image_key to
    # POST /api/v1/entries. ProcessEntryImageJob converts HEIC and resizes, as for MCP.
    class ImageUploadsController < BaseController
      before_action :require_pro!

      def create
        result = Mcp::PresignedImageUpload.new(user: current_user).call(
          filename: params[:filename],
          content_type: params[:content_type]
        )
        return render_error(:unprocessable_content, 'invalid', 'Could not prepare the upload.', details: result[:errors]) unless result[:success]

        render json: result.except(:success), status: :created
      end
    end
  end
end
