# frozen_string_literal: true

module Api
  module V1
    # Export Entries, from the app: the same export of the whole journal the Export page starts
    # (Export.request_for), with the link emailed as the web emails it. The app never opens the
    # web for it, so no second sign-in. The emailed link still needs one to download.
    class ExportsController < BaseController
      # POST /api/v1/exports. 202 with {status, email}: "started" or "preparing" (the email is
      # on its way when it's ready) or "sent" (one from the last few hours can still be
      # downloaded; its email goes again). 429 when Export::HOURLY_LIMIT is reached, or after
      # RESEND_LIMIT re-sends in an hour.
      RESEND_LIMIT = 5

      def create
        status, export = Export.request_for(current_user)
        case status
        when :limited
          return render_limit
        when :ready
          # The web downloads it on the spot; the app has nowhere to, so the link goes again,
          # a few times an hour a person (every device and token together) and no more.
          return render_limit if resends_this_hour > RESEND_LIMIT

          UserMailer.export_ready(export).deliver_later
          status = :sent
        end

        render json: { status: status, email: current_user.email }, status: :accepted
      end

      private

      def resends_this_hour
        Rails.cache.increment("api/exports/resends/#{current_user.id}", 1, expires_in: 1.hour).to_i
      end

      def render_limit
        render_error(:too_many_requests, 'export_limit',
                     "You've requested a lot of exports in the last hour. Please try again later.")
      end
    end
  end
end
