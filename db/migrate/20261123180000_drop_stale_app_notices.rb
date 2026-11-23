# The yearly unused-apps email (StaleConnectedAppsWorker) is gone: connected apps are now
# disconnected after 30 days unused (OauthIdleExpiry), so none can reach a year.
class DropStaleAppNotices < ActiveRecord::Migration[8.1]
  def change
    drop_table :stale_app_notices do |t|
      t.references :user, null: false, type: :integer, index: false, foreign_key: { on_delete: :cascade }
      t.references :oauth_application, null: false, index: true,
                                       foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.datetime :last_used_at, null: false
      t.datetime :notified_at, null: false
      t.index %i[user_id oauth_application_id], unique: true
    end
  end
end
