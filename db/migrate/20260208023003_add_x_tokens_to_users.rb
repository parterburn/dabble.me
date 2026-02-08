class AddXTokensToUsers < ActiveRecord::Migration[6.1]
  def change
    remove_column :users, :x_access_token_ciphertext, :text, if_exists: true
    remove_column :users, :x_refresh_token_ciphertext, :text, if_exists: true
    add_column :users, :x_access_token, :text unless column_exists?(:users, :x_access_token)
    add_column :users, :x_refresh_token, :text unless column_exists?(:users, :x_refresh_token)
    add_column :users, :x_uid, :string unless column_exists?(:users, :x_uid)
    add_column :users, :x_username, :string unless column_exists?(:users, :x_username)
  end
end
