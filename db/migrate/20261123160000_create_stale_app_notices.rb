# One row per connected app (OAuth client) a user was emailed about for going unused for a
# year (StaleConnectedAppsWorker). last_used_at is the last use the email named: the app is
# named again only after it is used and then goes another year unused.
class CreateStaleAppNotices < ActiveRecord::Migration[8.1]
  def change
    create_table :stale_app_notices do |t|
      t.references :user, null: false, type: :integer, index: false, foreign_key: { on_delete: :cascade }
      t.references :oauth_application, null: false, index: true,
                                       foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.datetime :last_used_at, null: false
      t.datetime :notified_at, null: false
    end
    add_index :stale_app_notices, %i[user_id oauth_application_id], unique: true
  end
end
