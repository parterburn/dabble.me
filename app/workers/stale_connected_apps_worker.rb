# frozen_string_literal: true

# Emails users about connected apps (Claude, ChatGPT, other MCP clients) that can still reach
# their journal but haven't been used in a year (ConnectedAppUsage::STALE_AFTER), listing them
# with a link to Connected apps to remove them.
#
# No nagging: an app is named again only if it is used after the last email and then goes
# another year unused (StaleAppNotice), and a user gets at most one of these every
# MIN_GAP; apps that go stale in between wait for the next one. Every currently stale app is
# listed, so one email gives the whole picture.
#
# It's an account security notice, like "New app connected", so it goes out whatever the
# user's entry-email schedule is. Deleted accounts are skipped.
class StaleConnectedAppsWorker
  include Sidekiq::Job

  sidekiq_options retry: false, queue: :default

  MIN_GAP = 90.days

  StaleApp = Struct.new(:application, :last_used_at, keyword_init: true)

  def perform
    sent = self.class.deliver_all
    Rails.logger.info("[StaleConnectedAppsWorker] emailed #{sent} users about unused connected apps")
    sent
  end

  def self.deliver_all(now: Time.current)
    ConnectedAppUsage.stale_by_user(now: now).count do |user_id, application_ids|
      deliver_to(user_id, application_ids, now: now)
    rescue StandardError => e
      Sentry.capture_exception(e, extra: { user_id: user_id })
      false
    end
  end

  def self.deliver_to(user_id, application_ids, now: Time.current)
    user = User.not_deleted.find_by(id: user_id)
    return false unless user
    return false if StaleAppNotice.where(user_id: user.id, notified_at: (now - MIN_GAP)..).exists?

    last_used = ConnectedAppUsage.last_used(user.id, application_ids)
    stale_ids = application_ids.select { |id| ConnectedAppUsage.stale?(last_used[id], now: now) }
    notices = StaleAppNotice.where(user_id: user.id, oauth_application_id: stale_ids).index_by(&:oauth_application_id)
    return false if stale_ids.none? { |id| notices[id].nil? || notices[id].last_used_at < last_used[id] }

    apps = Doorkeeper::Application.where(id: stale_ids).sort_by { |app| [app.name.downcase, app.created_at] }
    UserMailer.stale_connected_apps(user, apps.map { |app| StaleApp.new(application: app, last_used_at: last_used[app.id]) }).deliver_now

    StaleAppNotice.upsert_all(
      apps.map { |app| { user_id: user.id, oauth_application_id: app.id, last_used_at: last_used[app.id], notified_at: now } },
      unique_by: %i[user_id oauth_application_id]
    )
    true
  end
end
