# Where an account was created: "web" (the sign-up form) or "ios_app" (the app's native
# sign-up), with room for "android_app". Accounts from before this column stay NULL, shown as
# "Unknown" on Admin Stats: there's no reliable way to tell after the fact.
class AddSignupPlatformToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :signup_platform, :string
  end
end
