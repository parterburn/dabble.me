# Deletes OAuth clients that registered themselves (Oauth::RegistrationsController)
# and then went unused: MCP connectors register again on reconnects and new
# devices, and anyone can register one, so these pile up.
#
# A registration is deleted when it is older than STALE_AFTER, nobody holds an
# unrevoked token for it, and it hasn't issued a token or grant in STALE_AFTER.
# Admin-made (confidential) clients and the iOS app are never touched.
class OauthAppCleanupWorker
  include Sidekiq::Job

  sidekiq_options retry: false, queue: :default

  STALE_AFTER = 30.days
  SELF_REGISTERED_SCOPES = "mcp:access".freeze

  def self.stale_applications(now: Time.current)
    cutoff = now - STALE_AFTER
    Doorkeeper::Application
      .where(confidential: false, scopes: SELF_REGISTERED_SCOPES, owner_id: nil)
      .where.not(uid: MobileApp::CLIENT_ID)
      .where(created_at: ...cutoff)
      .where.not(id: Doorkeeper::AccessToken.where(revoked_at: nil).select(:application_id))
      .where.not(id: Doorkeeper::AccessToken.where(created_at: cutoff..).select(:application_id))
      .where.not(id: Doorkeeper::AccessGrant.where(created_at: cutoff..).select(:application_id))
  end

  def perform
    deleted = 0
    self.class.stale_applications.find_each do |application|
      application.destroy
      deleted += 1
    end
    Rails.logger.info("[OauthAppCleanupWorker] deleted #{deleted} unused OAuth registrations")
    deleted
  end
end
