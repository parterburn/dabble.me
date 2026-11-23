# frozen_string_literal: true

# Nightly: revokes connected-app tokens unused past their idle limit (OauthIdleExpiry), so the
# app is disconnected and drops off Connected apps. The iOS app's sign-in then leaves the
# Sessions list with UserSessionCleanupWorker. No email.
class OauthIdleTokenWorker
  include Sidekiq::Job

  sidekiq_options retry: false, queue: :default

  def perform
    revoked = OauthIdleExpiry.idle_tokens.update_all(revoked_at: Time.current)
    Rails.logger.info("[OauthIdleTokenWorker] revoked #{revoked} idle OAuth tokens")
    revoked
  end
end
