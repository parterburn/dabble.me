# The iOS app's settings that belong to the account rather than the phone (the entry template,
# what the Home Screen widget shows), so signing out or reinstalling doesn't lose them.
# JSON, encrypted like the other things a user writes (`encrypts :app_settings`).
class AddAppSettingsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :app_settings, :text
  end
end
