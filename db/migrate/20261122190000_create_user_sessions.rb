# The devices signed in to an account, for the Sessions list on Account Security and for signing
# one out (UserSession). A web browser is one row per sign-in; the iOS app is one row per sign-in,
# carried from token to token as it refreshes (oauth_access_tokens.user_session_id).
#
# Minimal on purpose: a browser and OS label, a coarse place (Cloudflare's city, region and
# country headers), and when it was last used. No IP address and no history of places.
#
# users.session_salt goes into Devise's authenticatable_salt (User::SessionRevocation): changing
# it ends every web session and "Stay logged in" cookie at once (Sign out of all devices).
class CreateUserSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :user_sessions do |t|
      t.references :user, null: false, type: :integer, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      # SHA-256 of the browser's token (in its session and device cookies). Null for the app.
      t.string :token_digest
      t.string :browser
      t.string :os
      t.string :city
      t.string :region
      t.string :country
      t.datetime :last_active_at, null: false
      t.timestamps
    end
    add_index :user_sessions, :token_digest, unique: true
    add_index :user_sessions, :last_active_at

    add_column :oauth_access_tokens, :user_session_id, :bigint
    add_index :oauth_access_tokens, :user_session_id

    add_column :users, :session_salt, :string
  end
end
