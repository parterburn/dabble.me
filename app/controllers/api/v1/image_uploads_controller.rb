# frozen_string_literal: true

module Api
  module V1
    # Presigned S3 PUTs for an entry's photos (up to CollageGenerator::MAX_IMAGES). Pass the
    # returned uploaded_image_key values to POST /api/v1/entries as uploaded_image_keys: one
    # photo goes through ProcessEntryImageJob, several become a collage via ImageCollageJob.
    class ImageUploadsController < BaseController
      before_action :require_pro!

      # POST /api/v1/image_uploads { photos: [{ filename:, content_type: }, ...] }
      def create
        photos = Array(params[:photos])
        if photos.empty? || photos.size > CollageGenerator::MAX_IMAGES
          return render_error(:unprocessable_content, 'invalid', "Add between 1 and #{CollageGenerator::MAX_IMAGES} photos.")
        end

        presigner = Mcp::PresignedImageUpload.new(user: current_user)
        uploads = photos.map do |photo|
          result = presigner.call(filename: photo[:filename], content_type: photo[:content_type])
          return render_error(:unprocessable_content, 'invalid', 'Could not prepare the upload.', details: result[:errors]) unless result[:success]

          result.except(:success)
        end

        render json: { uploads: uploads }, status: :created
      end
    end
  end
end
