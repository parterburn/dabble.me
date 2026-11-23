# Dabble Me PRO bought in the iOS app (StoreKit 2, auto-renewable). See AppStore in app/lib.
#
# - users.apple_account_token: the UUID the app passes Apple as appAccountToken with each
#   purchase, so a transaction names the Dabble account that bought it.
# - apple_subscriptions: one row per Apple subscription (originalTransactionId), with the state
#   last read from Apple. A deleted account leaves its row behind with no user, so the same
#   Apple ID can restore onto a new account.
# - app_store_notifications: each App Store Server Notification once, by notificationUUID, so
#   a redelivered one does nothing.
# - payments.apple_transaction_id: a payment per Apple transaction, once.
class CreateAppleSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :apple_account_token, :uuid
    add_index :users, :apple_account_token, unique: true

    create_table :apple_subscriptions do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :original_transaction_id, null: false
      t.string :environment, null: false
      t.string :product_id, null: false
      t.string :last_transaction_id
      t.uuid :app_account_token
      t.string :ownership_type
      # Apple's subscription status: 1 active, 2 expired, 3 billing retry, 4 grace period, 5 revoked.
      t.integer :status
      t.datetime :expires_at
      t.datetime :grace_period_expires_at
      t.datetime :revoked_at
      t.boolean :auto_renew
      t.string :auto_renew_product_id
      # Apple's signedDate of the newest state applied. Older state is ignored.
      t.datetime :state_signed_at, null: false
      t.timestamps
    end
    add_index :apple_subscriptions, :original_transaction_id, unique: true

    create_table :app_store_notifications do |t|
      t.string :notification_uuid, null: false
      t.string :notification_type, null: false
      t.string :subtype
      t.string :environment
      t.string :original_transaction_id
      t.datetime :signed_at
      t.datetime :processed_at
      t.timestamps
    end
    add_index :app_store_notifications, :notification_uuid, unique: true
    add_index :app_store_notifications, :original_transaction_id

    add_column :payments, :apple_transaction_id, :string
    add_index :payments, :apple_transaction_id, unique: true, where: "apple_transaction_id IS NOT NULL"
  end
end
