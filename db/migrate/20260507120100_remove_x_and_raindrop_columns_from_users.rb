class RemoveXAndRaindropColumnsFromUsers < ActiveRecord::Migration[6.1]
  def change
    remove_column :users, :x_access_token, :text
    remove_column :users, :x_refresh_token, :text
    remove_column :users, :x_uid, :string
    remove_column :users, :x_username, :string
    remove_column :users, :raindrop_api_key, :string
  end
end
