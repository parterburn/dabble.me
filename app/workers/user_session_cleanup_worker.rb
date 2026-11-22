# Deletes Sessions-list rows (UserSession) that can't sign anything in any more:
# - a browser not seen in Devise.remember_for: its "Stay logged in" cookie has run out, and its
#   row would turn away any older session cookie anyway;
# - an app sign-in with no unrevoked token (the app signed out, or its tokens were revoked),
#   after a day, so a refresh in progress isn't caught.
class UserSessionCleanupWorker
  include Sidekiq::Job

  sidekiq_options retry: false, queue: :default

  APP_GRACE = 1.day

  def self.stale(now: Time.current)
    live_tokens = Doorkeeper::AccessToken.where(revoked_at: nil)
                                         .where('oauth_access_tokens.user_session_id = user_sessions.id')
    UserSession.web.where(last_active_at: ...(now - Devise.remember_for))
               .or(UserSession.ios_app.where(updated_at: ...(now - APP_GRACE)).where.not(live_tokens.arel.exists))
  end

  def perform
    deleted = self.class.stale.delete_all
    Rails.logger.info("[UserSessionCleanupWorker] deleted #{deleted} signed-out sessions")
    deleted
  end
end
