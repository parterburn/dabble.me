# frozen_string_literal: true

module Api
  module V1
    # The devices signed in to the account (UserSession), as on Account Security on the web.
    class DeviceSessionsController < BaseController
      # GET /api/v1/device_sessions
      def index
        sessions = current_user.user_sessions.listable.most_recent_first
        render json: { sessions: sessions.map { |session| serialize(session) } }
      end

      # DELETE /api/v1/device_sessions/:id (this device's own row signs the app out too)
      def destroy
        current_user.user_sessions.find(params[:id]).revoke!
        head :no_content
      end

      # DELETE /api/v1/device_sessions: Sign out of all devices, this app included.
      def destroy_all
        current_user.sign_out_everywhere!
        head :no_content
      end

      private

      def serialize(session)
        {
          id: session.id,
          kind: session.kind,
          device: session.device_label,
          location: session.location_label,
          last_active_at: session.last_active_at.iso8601,
          signed_in_at: session.created_at.iso8601,
          current: session.id == Current.user_session&.id
        }
      end
    end
  end
end
