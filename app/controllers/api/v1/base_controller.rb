# frozen_string_literal: true

module Api
  module V1
    # JSON API for the first-party iOS app. Bearer tokens come from the MobileApp
    # OAuth client; MCP tokens (mcp:access) are rejected by the scope check.
    class BaseController < ActionController::API
      include Doorkeeper::Rails::Helpers

      before_action :authorize_app_token!
      before_action :ensure_account_active

      rescue_from ActiveRecord::RecordNotFound do
        render_error(:not_found, 'not_found', 'Entry not found.')
      end

      private

      # Sign-in and sign-up skip this: they're how the app gets a token.
      def authorize_app_token!
        doorkeeper_authorize! MobileApp::SCOPE
        track_app_session! unless performed?
      end

      # The device's row in the Sessions list (AppSessions). A token whose device was signed out
      # on dabble.me (or by Sign out of all devices) stops here.
      def track_app_session!
        return unless AppSessions.app_token?(doorkeeper_token)

        if (session = AppSessions.for_token(doorkeeper_token, current_user, request))
          Current.user_session = session
        else
          doorkeeper_token.revoke
          render json: { error: 'unauthorized', message: 'Sign in again to continue.' }, status: :unauthorized
        end
      end

      def current_user
        @current_user ||= User.find(doorkeeper_token.resource_owner_id).tap do |user|
          Sentry.set_user(id: user.id)
          Sentry.set_tags(mobile_api: true)
        end
      end

      def ensure_account_active
        return unless current_user.deletion_pending?

        render_error(:forbidden, 'account_pending_deletion',
                     'This account is scheduled for deletion. Sign in again to keep it.')
      end

      # PRO-only features (see each controller for which). Free accounts read and write
      # text entries; the app shows these as PRO without linking to a purchase.
      def require_pro!
        return if current_user.is_pro?

        render_error(:forbidden, 'pro_required', 'This is part of Dabble Me PRO.')
      end

      def render_error(status, code, message, details: nil)
        payload = { error: code, message: message }
        payload[:details] = details if details.present?
        render json: payload, status: status
      end

      def page_param
        params[:page].to_s.match?(/\A\d+\z/) ? [params[:page].to_i, 1].max : 1
      end

      def per_page_param(default: 20)
        per = params[:per].to_s.match?(/\A\d+\z/) ? params[:per].to_i : default
        per.clamp(1, 50)
      end

      def paginated(relation)
        page = relation.page(page_param).per(per_page_param)
        {
          entries: page.map { |entry| EntrySerializer.summary(entry) },
          page: page.current_page,
          next_page: page.next_page,
          total_count: page.total_count
        }
      end

      def doorkeeper_unauthorized_render_options(error:)
        { json: { error: 'unauthorized', message: 'Sign in again to continue.' } }
      end

      def doorkeeper_forbidden_render_options(error:)
        { json: { error: 'forbidden', message: 'This token cannot be used with the Dabble Me app API.' } }
      end
    end
  end
end
