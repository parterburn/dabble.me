# frozen_string_literal: true

module AppStore
  # App Store Server Notifications V2, for production and sandbox alike (App Store Connect →
  # the app → App Information → App Store Server Notifications, Version 2). No session or CSRF
  # token: what proves it came from Apple is the payload's signature (AppStore::Notification).
  #
  # 200 tells Apple it's done, including for a notification seen before. Anything else and
  # Apple redelivers it later (after 1, 12, 24, 48 and 72 hours).
  class NotificationsController < ActionController::API
    MAX_BODY_BYTES = 64.kilobytes

    def create
      return head(:content_too_large) if request.content_length.to_i > MAX_BODY_BYTES

      body = request.raw_post.to_s
      return head(:content_too_large) if body.bytesize > MAX_BODY_BYTES

      signed_payload = JSON.parse(body)["signedPayload"] rescue nil
      return head(:bad_request) unless signed_payload.is_a?(String)

      AppStore::Notification.process!(signed_payload)
      head :ok
    rescue AppStore::VerificationError => e
      Sentry.capture_message("App Store notification refused", level: :warning, extra: { reason: e.message })
      head :bad_request
    rescue AppStore::TransientError => e
      Sentry.capture_exception(e, level: :warning)
      head :service_unavailable
    end
  end
end
